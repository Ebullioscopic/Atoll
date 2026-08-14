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

import Combine
import Defaults
import Foundation

/// Tracks the AI coding agent sessions running on this Mac.
///
/// Sessions are reconstructed purely from hook events the agents fire — Atoll
/// never scrapes a terminal or polls a process list.
///
/// This phase is read-only. Every hook Atoll registers is observe-only: the shim
/// drops its request and exits without waiting, so nothing an agent does is ever
/// gated on Atoll being present or correct. The approval flow, which is the only
/// thing that will ever return a decision, lands in a later phase behind
/// ``Defaults/agentTowerApprovalsEnabled``.
@MainActor
final class AgentTowerManager: ObservableObject {
    static let shared = AgentTowerManager()

    /// Newest activity first, which is the order the notch shows them in.
    @Published private(set) var sessions: [AgentSession] = []
    /// Non-nil when the feature could not be armed; surfaced in Settings.
    @Published private(set) var setupError: String?
    @Published private(set) var isArmed = false
    /// Which agents currently have Atoll's hooks in their config.
    @Published private(set) var installedKinds: Set<AgentKind> = []
    /// Per-agent install failure, keyed by agent. Shown inline in Settings.
    @Published private(set) var installErrors: [AgentKind: String] = [:]

    private let spool = AgentHookSpool()
    private var cancellables = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?
    private var hasStarted = false

    /// Sessions kept in memory. Well above any realistic number of concurrent
    /// agents; the cap exists so a misbehaving hook cannot grow the list without
    /// bound.
    private static let maxSessions = 64

    private init() {}

    // MARK: - Derived state

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status != .idle }
    }

    var runningCount: Int {
        sessions.filter { $0.status == .working }.count
    }

    var waitingCount: Int {
        sessions.filter { $0.status == .waitingOnUser }.count
    }

    var finishedCount: Int {
        sessions.filter { $0.status == .finished }.count
    }

    /// Whether the notch has anything worth showing.
    var hasVisibleActivity: Bool {
        Defaults[.enableAgentTower] && !activeSessions.isEmpty
    }

    /// Agents Atoll can configure that also look installed on this Mac.
    var availableKinds: [AgentKind] {
        AgentKind.allCases.filter { kind in
            guard let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: false) else {
                return false
            }
            return AgentHookInstaller.isAgentPresent(descriptor)
        }
    }

    // MARK: - Lifecycle

    /// Wires observers and arms the spool if the feature is on.
    ///
    /// Deliberately not done in `init()`: touching `Defaults.publisher` or another
    /// shared manager from a singleton's initialiser deadlocks app launch. Called
    /// from `applicationDidFinishLaunching`.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        sessions = loadSessions()
        pruneStaleSessions()

        Defaults.publisher(.enableAgentTower)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.applyEnabledState(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.agentTowerEnabledKinds)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, Defaults[.enableAgentTower] else { return }
                self.synchronizeHooks()
            }
            .store(in: &cancellables)

        applyEnabledState(Defaults[.enableAgentTower])
    }

    /// Disarms the spool.
    ///
    /// Removing the heartbeat is what releases any shim that happens to be
    /// waiting: each one re-checks it while polling and exits with no output, so
    /// quitting Atoll can never leave a session hanging.
    func shutdown() {
        spool.stop()
        isArmed = false
        saveSessionsNow()
    }

    private func applyEnabledState(_ isEnabled: Bool) {
        if isEnabled {
            arm()
        } else {
            spool.stop()
            isArmed = false
            removeAllHooks()
        }
    }

    private func arm() {
        guard !spool.isRunning else { return }

        do {
            try AgentHookInstaller.writeShim()
        } catch {
            setupError = error.localizedDescription
            return
        }

        guard spool.start(handler: { [weak self] envelope in
            await self?.handle(envelope) ?? nil
        }) else {
            setupError = String(localized: "Atoll could not prepare its hook folder. Check that ~/.atoll is owned by you and not shared.")
            isArmed = false
            return
        }

        setupError = nil
        isArmed = true
        synchronizeHooks()
    }

    // MARK: - Hook handling

    /// Handles one hook invocation.
    ///
    /// Returns the bytes the agent will read as its hook's stdout, or `nil` for
    /// "no decision". This phase always returns `nil`, and the events it
    /// registers are observe-only anyway, so nothing is waiting on the answer.
    private func handle(_ envelope: AgentHookEnvelope) async -> Data? {
        guard let event = AgentEventAdapter.makeEvent(
            body: envelope.payload,
            agentHint: envelope.agent,
            eventHint: envelope.event,
            terminalProgram: envelope.terminalProgram,
            terminalBundleID: envelope.terminalBundleID,
            now: Date()
        ) else {
            Logger.log("Agent Tower: dropped a \(envelope.event) payload with no session id", category: .agents)
            return nil
        }

        ingest(event, agentPID: envelope.agentPID)
        return nil
    }

    /// Folds an event into the session list.
    func ingest(_ event: AgentHookEvent, agentPID: Int32? = nil) {
        // Ignore agents the user has not opted into, so turning one off stops it
        // appearing even if a stale hook entry survives somewhere.
        guard Defaults[.agentTowerEnabledKinds].contains(event.kind) else { return }

        if let index = sessions.firstIndex(where: { $0.id == event.sessionKey }) {
            sessions[index].apply(event)
            if let agentPID { sessions[index].agentPID = agentPID }
            let updated = sessions.remove(at: index)
            sessions.insert(updated, at: 0)
        } else {
            var session = AgentSession(event: event)
            session.apply(event)
            session.agentPID = agentPID
            sessions.insert(session, at: 0)
            if sessions.count > Self.maxSessions {
                sessions.removeLast(sessions.count - Self.maxSessions)
            }
        }

        scheduleSave()
    }

    /// Clears a finished session's card.
    func acknowledge(sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].status = .idle
        scheduleSave()
    }

    func remove(sessionID: String) {
        sessions.removeAll { $0.id == sessionID }
        scheduleSave()
    }

    func clearInactiveSessions() {
        sessions.removeAll { $0.status == .finished || $0.status == .idle }
        scheduleSave()
    }

    // MARK: - Hook installation

    /// Brings every agent's config in line with the current settings: enabled
    /// agents get Atoll's hooks, disabled ones have them removed.
    func synchronizeHooks() {
        guard Defaults[.enableAgentTower] else { return }

        do {
            try AgentHookInstaller.writeShim()
        } catch {
            setupError = error.localizedDescription
            return
        }

        let wanted = Set(Defaults[.agentTowerEnabledKinds])
        let includeApprovals = Defaults[.agentTowerApprovalsEnabled]
        var installed: Set<AgentKind> = []
        var errors: [AgentKind: String] = [:]

        for kind in AgentKind.allCases {
            guard let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: includeApprovals) else {
                continue
            }
            do {
                if wanted.contains(kind), AgentHookInstaller.isAgentPresent(descriptor) {
                    try AgentHookInstaller.install(descriptor: descriptor)
                    installed.insert(kind)
                } else {
                    try AgentHookInstaller.uninstall(descriptor: descriptor)
                }
            } catch {
                errors[kind] = error.localizedDescription
                Logger.log(
                    "Agent Tower: hook update failed for \(kind.displayName): \(error.localizedDescription)",
                    category: .agents
                )
            }
        }

        installedKinds = installed
        installErrors = errors
    }

    /// Strips Atoll's entries from every agent config and deletes the shim.
    ///
    /// Also exposed in Settings so the user can undo everything in one action
    /// instead of hunting through config files.
    func removeAllHooks() {
        var errors: [AgentKind: String] = [:]
        for kind in AgentKind.allCases {
            guard let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: true) else {
                continue
            }
            do {
                try AgentHookInstaller.uninstall(descriptor: descriptor)
            } catch {
                errors[kind] = error.localizedDescription
            }
        }
        AgentHookInstaller.removeShim()
        installedKinds = []
        installErrors = errors
    }

    /// Re-reads each config so Settings reflects reality rather than intent.
    func refreshInstallationState() {
        var installed: Set<AgentKind> = []
        for kind in AgentKind.allCases {
            guard let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: false) else {
                continue
            }
            if AgentHookInstaller.isInstalled(descriptor: descriptor) {
                installed.insert(kind)
            }
        }
        installedKinds = installed
    }

    // MARK: - Persistence

    /// Coalesces bursts of events into one write. A busy agent fires several
    /// hooks a second and each would otherwise re-serialise the whole list.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveSessionsNow()
        }
    }

    private func saveSessionsNow() {
        saveTask?.cancel()
        saveTask = nil

        // Live statuses are meaningless after a relaunch — the hook processes
        // that were mid-flight are gone — so persist them as idle.
        let snapshot = sessions.map { session -> AgentSession in
            var copy = session
            if copy.status == .working || copy.status == .waitingOnUser {
                copy.status = .idle
            }
            return copy
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: AgentTowerStorage.sessionsURL, options: .atomic)
    }

    private func loadSessions() -> [AgentSession] {
        guard let data = try? Data(contentsOf: AgentTowerStorage.sessionsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let restored = try? decoder.decode([AgentSession].self, from: data) else { return [] }
        return restored.map { session in
            var copy = session
            copy.status = copy.status == .finished ? .finished : .idle
            return copy
        }
    }

    /// Drops sessions whose agent process is gone, whose project directory has
    /// disappeared, or that are older than the configured window.
    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-Double(Defaults[.agentTowerSessionPruneHours]) * 3600)
        let fm = FileManager.default
        sessions.removeAll { session in
            if session.lastActivityAt < cutoff { return true }
            if let cwd = session.cwd, !cwd.isEmpty, !fm.fileExists(atPath: cwd) { return true }
            // `kill(pid, 0)` only probes for existence; it sends no signal.
            if let pid = session.agentPID, pid > 0, kill(pid, 0) != 0, errno == ESRCH { return true }
            return false
        }
    }
}
