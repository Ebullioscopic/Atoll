/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// One hook invocation, as the shim wrote it into the spool.
struct AgentHookEnvelope: Sendable {
    /// Spool protocol version. A shim from a different Atoll version is ignored
    /// rather than guessed at.
    let version: Int
    /// Request identifier, also the `out/<id>` filename the shim is watching.
    let id: String
    /// Wire event name, passed as an argument so the shim never parses the body.
    let event: String
    /// `AgentKind.rawValue`, likewise passed as an argument.
    let agent: String
    /// Whether the shim is blocked waiting for a decision. Observe-only hooks
    /// drop their file and exit immediately, so nothing is ever written back.
    let expectsDecision: Bool
    /// The agent process id — the shim's own parent.
    let agentPID: Int32?
    let terminalProgram: String?
    let terminalBundleID: String?
    /// The agent's hook payload, re-serialised verbatim.
    let payload: Data
}

/// File-based transport between the hook shim and Atoll.
///
/// ## Why a spool and not a local socket
/// A directory at mode `0700` is gated by the kernel on uid. A TCP port, even on
/// loopback, is reachable by anything that can make a connection — including a
/// web page via a localhost request, and any container or VM with host
/// networking. The socket design would have to defend that class with `Origin`
/// and `Host` checks; the spool does not have the class at all.
///
/// Three more properties fall out of it:
/// - **Observe-only hooks cost one file write.** No round trip, no waiting — so
///   the common case is faster than a socket, not slower.
/// - **A blocked request survives an Atoll restart.** The request file is still
///   in `in/`, so the pending card comes back instead of being stranded.
/// - **No `curl` dependency and no hand-written HTTP parsing.**
///
/// ## The invariant to preserve
/// The spool **accepts requests and never accepts decisions**. A decision for
/// request `id` is only ever written by Atoll to `out/<id>.json`, and only the
/// process that created `in/<id>.json` reads it. So a hostile same-uid process
/// can fabricate a card in the notch, but it cannot cause *another* agent's
/// command to be approved. Do not add a path that lets anything outside Atoll
/// supply a decision.
///
/// Same-uid code execution is otherwise out of scope and undefendable: such code
/// could rewrite the agent's config or replace the shim outright. The mode-`0700`
/// check defends against *other* local users, which is a boundary the kernel can
/// actually enforce.
final class AgentHookSpool: @unchecked Sendable {
    /// Bumped whenever the envelope shape or the shim contract changes. The shim
    /// stamps it, and a mismatch is dropped rather than interpreted.
    static let protocolVersion = 1
    /// Largest request file read. Plans and diffs stay far below this.
    static let maxRequestBytes = 1 << 20
    /// Requests older than this are garbage — the shim that wrote them has long
    /// since timed out and exited.
    private static let staleRequestAge: TimeInterval = 15 * 60

    /// Called for each accepted request. Returning `nil` means "no decision".
    /// Only consulted when `expectsDecision` is true.
    typealias Handler = @Sendable (AgentHookEnvelope) async -> Data?

    private let queue = DispatchQueue(label: "com.ebullioscopic.Atoll.agentTower.spool", qos: .userInitiated)
    private let lock = NSLock()

    private var watchSource: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var heartbeatTimer: DispatchSourceTimer?
    private var handler: Handler?
    private var isArmed = false
    /// Request ids already handed to the handler, so a directory event that
    /// re-lists a file cannot double-process it.
    private var seenRequestIDs: Set<String> = []
    /// Request ids already answered. Claimed *before* the body is written, so a
    /// second decision cannot overwrite the first one's payload.
    private var answeredRequestIDs: Set<String> = []

    // MARK: - Lifecycle

    /// Arms the spool: prepares the directories, starts the heartbeat and begins
    /// watching for requests.
    ///
    /// - Returns: `false` when the spool cannot be trusted (wrong owner or
    ///   permissions). Callers must not proceed — Atoll would be reading command
    ///   text out of, and writing permission decisions into, a directory someone
    ///   else can touch.
    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isArmed else { return true }
        guard AgentTowerStorage.prepareSpool() else { return false }

        self.handler = handler
        isArmed = true

        touchHeartbeat()
        startHeartbeat()
        startWatching()

        // Pick up anything queued while Atoll was not running, then sweep.
        queue.async { [weak self] in
            self?.scanInbox()
            self?.collectGarbage()
        }
        Logger.log("Agent Tower: spool armed at \(AgentTowerStorage.spoolDirectory.path)", category: .agents)
        return true
    }

    /// Disarms the spool and removes the heartbeat.
    ///
    /// Deleting `alive` is what releases blocked shims: each one re-checks the
    /// heartbeat while polling and exits with no output as soon as it goes away,
    /// so the agent falls back to its own prompt instead of waiting out the
    /// timeout.
    func stop() {
        lock.lock()
        let source = watchSource
        let descriptor = watchedDescriptor
        watchSource = nil
        watchedDescriptor = -1
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        handler = nil
        isArmed = false
        seenRequestIDs.removeAll()
        answeredRequestIDs.removeAll()
        lock.unlock()

        source?.cancel()
        if source == nil, descriptor >= 0 {
            close(descriptor)
        }
        try? FileManager.default.removeItem(at: AgentTowerStorage.heartbeatURL)
        Logger.log("Agent Tower: spool disarmed", category: .agents)
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isArmed
    }

    // MARK: - Heartbeat

    /// Touches `alive` so shims know Atoll is still answering.
    private func touchHeartbeat() {
        let url = AgentTowerStorage.heartbeatURL
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        } else {
            try? Data().write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + AgentTowerStorage.heartbeatInterval,
            repeating: AgentTowerStorage.heartbeatInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunning else { return }
            self.touchHeartbeat()
            // Directory watches can coalesce or miss bursts, so the heartbeat
            // tick doubles as a cheap backstop scan.
            self.scanInbox()
            self.collectGarbage()
        }
        heartbeatTimer = timer
        timer.resume()
    }

    // MARK: - Watching

    /// Watches the inbox directory. Modelled on `DownloadManager`'s
    /// `DispatchSource.makeFileSystemObjectSource` usage.
    private func startWatching() {
        let path = AgentTowerStorage.inboxDirectory.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            Logger.log("Agent Tower: could not watch \(path)", category: .agents)
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scanInbox()
        }
        source.setCancelHandler {
            close(descriptor)
        }

        watchedDescriptor = descriptor
        watchSource = source
        source.resume()
    }

    // MARK: - Inbox

    /// Reads every complete request file and dispatches it.
    ///
    /// Runs on `queue`; safe to call repeatedly.
    private func scanInbox() {
        let fm = FileManager.default
        let inbox = AgentTowerStorage.inboxDirectory
        guard let names = try? fm.contentsOfDirectory(atPath: inbox.path) else { return }

        // `.tmp` files are mid-write; the shim renames into place, so only the
        // final name is ever read.
        for name in names.sorted() where name.hasSuffix(".json") {
            let url = inbox.appendingPathComponent(name)
            process(requestAt: url)
        }
    }

    private func process(requestAt url: URL) {
        let fm = FileManager.default

        // A file we do not exclusively own is not one we will act on.
        guard AgentTowerStorage.isPrivatelyOwned(url) else {
            Logger.log("Agent Tower: discarded \(url.lastPathComponent) — wrong owner or permissions", category: .agents)
            try? fm.removeItem(at: url)
            return
        }

        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { return }  // still being written
        guard size <= Self.maxRequestBytes else {
            Logger.log("Agent Tower: discarded an oversized request (\(size) bytes)", category: .agents)
            try? fm.removeItem(at: url)
            return
        }

        guard let data = try? Data(contentsOf: url) else { return }
        guard let envelope = Self.decode(data) else {
            Logger.log("Agent Tower: discarded an unreadable request \(url.lastPathComponent)", category: .agents)
            try? fm.removeItem(at: url)
            return
        }

        lock.lock()
        let alreadySeen = seenRequestIDs.contains(envelope.id)
        if !alreadySeen { seenRequestIDs.insert(envelope.id) }
        let currentHandler = handler
        lock.unlock()

        guard !alreadySeen, let currentHandler else { return }

        // An observe-only request is consumed here and now; nothing is waiting on
        // it. A decision request keeps its file until answered, so an Atoll
        // restart can rediscover it.
        if !envelope.expectsDecision {
            try? fm.removeItem(at: url)
        }

        Task { [weak self] in
            let response = await currentHandler(envelope)
            guard envelope.expectsDecision else { return }
            self?.respond(to: envelope.id, body: response ?? Data())
            try? fm.removeItem(at: url)
        }
    }

    /// Decodes an envelope, refusing anything from a different protocol version.
    static func decode(_ data: Data) -> AgentHookEnvelope? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { return nil }

        guard let version = root["v"] as? Int, version == protocolVersion else { return nil }
        guard let id = root["id"] as? String, !id.isEmpty else { return nil }
        guard let event = root["event"] as? String else { return nil }
        guard let agent = root["agent"] as? String else { return nil }
        guard let payloadObject = root["payload"] else { return nil }
        guard let payload = try? JSONSerialization.data(withJSONObject: payloadObject) else { return nil }

        return AgentHookEnvelope(
            version: version,
            id: id,
            event: event,
            agent: agent,
            expectsDecision: (root["wait"] as? Bool) ?? false,
            agentPID: (root["pid"] as? NSNumber)?.int32Value,
            terminalProgram: nonEmpty(root["term"] as? String),
            terminalBundleID: nonEmpty(root["termbid"] as? String),
            payload: payload
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Outbox

    /// Writes a decision for a blocked shim.
    ///
    /// Ordering matters twice over, and both orderings are load-bearing:
    ///
    /// 1. **The request is claimed before anything is written.** A user tapping
    ///    Approve at the same moment the expiry timer fires would otherwise have
    ///    the second decision overwrite the first one's body — while the first
    ///    one's sentinel already told the shim to read it. The claim is in memory
    ///    because Atoll is the only writer.
    /// 2. **The body is written before the sentinel.** The shim polls for
    ///    `out/<id>.done` and only then reads `out/<id>.json`, so it can never
    ///    observe a half-written payload. `O_EXCL` on the sentinel is a second
    ///    layer that also rejects a stale one left by a previous run.
    func respond(to requestID: String, body: Data) {
        guard Self.isSafeRequestID(requestID) else { return }

        lock.lock()
        let alreadyAnswered = answeredRequestIDs.contains(requestID)
        if !alreadyAnswered { answeredRequestIDs.insert(requestID) }
        lock.unlock()

        guard !alreadyAnswered else { return }

        let outbox = AgentTowerStorage.outboxDirectory
        let bodyURL = outbox.appendingPathComponent("\(requestID).json")
        let doneURL = outbox.appendingPathComponent("\(requestID).done")

        do {
            try body.write(to: bodyURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
        } catch {
            Logger.log("Agent Tower: could not write a decision: \(error.localizedDescription)", category: .agents)
            // Release the claim so a retry is possible.
            lock.lock()
            answeredRequestIDs.remove(requestID)
            lock.unlock()
            return
        }

        let descriptor = open(doneURL.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        if descriptor >= 0 { close(descriptor) }
    }

    /// Request ids come from a shim we wrote, but they are still used to build a
    /// path, so treat them as untrusted input.
    static func isSafeRequestID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 128 else { return false }
        return id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    // MARK: - Garbage collection

    /// Removes abandoned request files, orphaned responses and stale bookkeeping.
    ///
    /// Necessary because a shim killed with SIGKILL cannot clean up after itself,
    /// and because the spool holds command text that should not linger.
    private func collectGarbage() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Self.staleRequestAge)

        for directory in [AgentTowerStorage.inboxDirectory, AgentTowerStorage.outboxDirectory] {
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names {
                let url = directory.appendingPathComponent(name)
                let attributes = try? fm.attributesOfItem(atPath: url.path)
                let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
                if modified < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
        }

        // Keep the bookkeeping sets from growing without bound over a long
        // uptime, but only by dropping ids whose file is already gone — a
        // wholesale clear would let a still-pending request be processed twice,
        // or let its answered decision body be overwritten.
        lock.lock()
        if seenRequestIDs.count > 4096 {
            let live = Self.requestIDs(inFilesNamed: (try? fm.contentsOfDirectory(atPath: AgentTowerStorage.inboxDirectory.path)) ?? [])
            seenRequestIDs.formIntersection(live)
        }
        if answeredRequestIDs.count > 4096 {
            let live = Self.requestIDs(inFilesNamed: (try? fm.contentsOfDirectory(atPath: AgentTowerStorage.outboxDirectory.path)) ?? [])
            answeredRequestIDs.formIntersection(live)
        }
        lock.unlock()
    }

    /// Recovers request ids from spool filenames (`<id>.json`, `<id>.done`).
    private static func requestIDs(inFilesNamed names: [String]) -> Set<String> {
        Set(names.compactMap { name in
            for suffix in [".json", ".done"] where name.hasSuffix(suffix) {
                return String(name.dropLast(suffix.count))
            }
            return nil
        })
    }
}
