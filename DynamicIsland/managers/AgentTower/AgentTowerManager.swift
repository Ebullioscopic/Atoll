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

import AppKit
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

    /// Requests waiting on the user, newest first.
    @Published private(set) var pendingRequests: [AgentPendingRequest] = []

    private let spool = AgentHookSpool()
    private let ruleStore = AgentApprovalRuleStore()
    /// One continuation per blocked hook. Resuming it is what unblocks the agent,
    /// so every path out of a pending request must go through `resolve`.
    private var decisionContinuations: [String: CheckedContinuation<AgentDecision, Never>] = [:]
    private var expiryTasks: [String: Task<Void, Never>] = [:]
    private var escalationTasks: [String: Task<Void, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?
    private var hasStarted = false
    /// Last transcript read per session, so a burst of hooks does not re-read a
    /// multi-megabyte file several times a second.
    private var lastContextReadAt: [String: Date] = [:]

    /// Minimum gap between transcript reads for one session.
    private static let contextRefreshInterval: TimeInterval = 2

    /// How long Atoll waits for the user before answering "no decision".
    ///
    /// Shorter than the shim's own polling deadline so the shim always reads a
    /// real answer and exits cleanly, instead of being cut off mid-wait.
    private static let decisionDeadline = TimeInterval(AgentHookInstaller.decisionTimeout - 5)

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

    /// Sessions that need the user. A pending approval counts even if the
    /// session's own status has not caught up yet.
    var waitingCount: Int {
        let waitingIDs = Set(pendingRequests.map(\.sessionID))
        return sessions.filter { $0.status == .waitingOnUser || waitingIDs.contains($0.id) }.count
    }

    /// The request the notch should show first: worst risk, then oldest.
    var frontmostRequest: AgentPendingRequest? {
        pendingRequests.max { lhs, rhs in
            if lhs.risk != rhs.risk { return lhs.risk < rhs.risk }
            return lhs.receivedAt > rhs.receivedAt
        }
    }

    /// Whether an approval is waiting, which is what the closed notch reacts to.
    var hasPendingApproval: Bool {
        !pendingRequests.isEmpty
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

        // Turning approvals on or off changes which hook events are installed, so
        // the configs have to be rewritten — and anything currently blocked has to
        // be released rather than left waiting on a feature that just went away.
        Defaults.publisher(.agentTowerApprovalsEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self, Defaults[.enableAgentTower] else { return }
                if !change.newValue { self.resolveAllPending() }
                self.synchronizeHooks()
            }
            .store(in: &cancellables)

        ruleStore.prune(liveSessionIDs: Set(sessions.map(\.id)))

        applyEnabledState(Defaults[.enableAgentTower])
    }

    /// Disarms the spool.
    ///
    /// Removing the heartbeat is what releases any shim that happens to be
    /// waiting: each one re-checks it while polling and exits with no output, so
    /// quitting Atoll can never leave a session hanging.
    func shutdown() {
        // Release blocked hooks before the spool goes away, so each agent gets a
        // real "no decision" instead of discovering the heartbeat is gone.
        resolveAllPending()
        spool.stop()
        isArmed = false
        saveSessionsNow()
    }

    private func applyEnabledState(_ isEnabled: Bool) {
        if isEnabled {
            arm()
        } else {
            resolveAllPending()
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

        // Only a hook that is actually blocked, for an event Atoll recognises as
        // a permission request, and only when the user has enabled approvals.
        guard envelope.expectsDecision,
              event.name.expectsDecision,
              Defaults[.agentTowerApprovalsEnabled],
              Defaults[.agentTowerEnabledKinds].contains(event.kind)
        else { return nil }

        let request = makeRequest(id: envelope.id, event: event)
        let cwd = sessions.first { $0.id == event.sessionKey }?.cwd

        // An existing rule answers without bothering the user. `match` refuses
        // outright for high-risk commands, so this can never silently approve one.
        if let rule = ruleStore.match(request, cwd: cwd) {
            Logger.log(
                "Agent Tower: auto-approved \(request.toolLabel) from a saved rule (\(rule.id))",
                category: .agents
            )
            return AgentDecisionEncoder.encode(.allowOnce, for: request)
        }

        let decision = await awaitDecision(for: request)
        return AgentDecisionEncoder.encode(decision, for: request)
    }

    /// Builds the request card from a hook event.
    private func makeRequest(id: String, event: AgentHookEvent) -> AgentPendingRequest {
        let detail: AgentRequestDetail
        if let command = event.command, !command.isEmpty {
            detail = .shellCommand(command)
        } else if let plan = event.plan, !plan.isEmpty, event.toolName?.lowercased().contains("plan") == true {
            detail = .plan(plan)
        } else if let path = event.filePath, !path.isEmpty {
            detail = .fileEdit(path: path, preview: event.toolDescription)
        } else {
            detail = .generic(event.toolDescription ?? event.message ?? event.toolName ?? event.rawEventName)
        }

        // Classification always runs, independent of the "flag destructive
        // commands" preference: that setting only controls whether the warning
        // banner is shown, not whether a persistent rule may be offered.
        let cwd = sessions.first { $0.id == event.sessionKey }?.cwd
        let flags: [CommandRiskFlag]
        if case .shellCommand(let command) = detail {
            flags = DestructiveCommandClassifier.evaluate(command: command, cwd: cwd)
        } else {
            flags = []
        }

        return AgentPendingRequest(
            id: id,
            sessionID: event.sessionKey,
            kind: event.kind,
            rawEventName: event.rawEventName,
            toolName: event.toolName,
            detail: detail,
            riskFlags: flags,
            receivedAt: event.receivedAt,
            expiresAt: event.receivedAt.addingTimeInterval(Self.decisionDeadline)
        )
    }

    /// Suspends until the user decides, a rule is not involved, or the deadline
    /// passes.
    private func awaitDecision(for request: AgentPendingRequest) async -> AgentDecision {
        await withCheckedContinuation { continuation in
            decisionContinuations[request.id] = continuation
            pendingRequests.insert(request, at: 0)

            // Answer slightly before the agent's own hook timeout, so the shim
            // always exits cleanly rather than being cut off mid-wait.
            expiryTasks[request.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.decisionDeadline))
                guard !Task.isCancelled else { return }
                self?.resolve(requestID: request.id, with: .noDecision)
            }

            startEscalation(for: request)
        }
    }

    // MARK: - Reminders

    /// Nudges the user along a widening ladder while a request goes unanswered.
    ///
    /// Runs the ladder as one task per request rather than a shared timer, so
    /// several waiting agents escalate independently and cancelling is exact.
    private func startEscalation(for request: AgentPendingRequest) {
        guard Defaults[.agentTowerEscalationEnabled] else { return }

        escalationTasks[request.id] = Task { [weak self] in
            for delay in AgentEscalationSchedule.deltas(for: AgentEscalationSchedule.defaultSteps) {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { return }
                self?.deliverReminder(for: request.id)
            }
        }
    }

    /// Shows the notch reminder for a still-pending request.
    private func deliverReminder(for requestID: String) {
        guard let request = pendingRequests.first(where: { $0.id == requestID }) else { return }

        let suppressed = AgentEscalationSchedule.shouldSuppressReminder(
            privacyMode: Defaults[.agentTowerPrivacyMode],
            doNotDisturbActive: DoNotDisturbManager.shared.isDoNotDisturbActive
        )
        // Privacy mode silences the nudge but leaves the card in place: the user
        // asked not to be interrupted, not to be kept in the dark.
        guard !suppressed else { return }

        let projectName = sessions.first { $0.id == request.sessionID }?.displayTitle ?? request.kind.displayName
        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .agentTower,
            duration: 3,
            icon: "hand.raised.fill",
            title: projectName,
            subtitle: request.toolLabel,
            accentColor: request.risk >= .high ? .red : .orange
        )

        if Defaults[.agentTowerPlaySound] {
            NSSound(named: request.risk >= .high ? "Basso" : "Tink")?.play()
        }
    }

    /// Answers a pending request. Safe to call twice; the second call is ignored.
    ///
    /// This is the only way a blocked hook is ever released, so it must not be
    /// bypassed — a request removed from `pendingRequests` without resuming its
    /// continuation would leave the agent waiting out its full timeout.
    func resolve(requestID: String, with decision: AgentDecision) {
        guard let continuation = decisionContinuations.removeValue(forKey: requestID) else { return }
        let request = pendingRequests.first { $0.id == requestID }

        expiryTasks.removeValue(forKey: requestID)?.cancel()
        escalationTasks.removeValue(forKey: requestID)?.cancel()
        pendingRequests.removeAll { $0.id == requestID }

        if let request, decision.createsRule {
            let cwd = sessions.first { $0.id == request.sessionID }?.cwd
            ruleStore.record(decision, for: request, cwd: cwd)
        }

        if let request {
            Logger.log(
                "Agent Tower: \(describe(decision)) \(request.toolLabel) for \(request.sessionID)",
                category: .agents
            )
        }
        continuation.resume(returning: decision)
    }

    /// Releases every blocked hook with "no decision".
    ///
    /// Used when the feature is switched off and when Atoll quits: an agent must
    /// never be left waiting because Atoll stopped caring.
    private func resolveAllPending(with decision: AgentDecision = .noDecision) {
        for id in decisionContinuations.keys {
            resolve(requestID: id, with: decision)
        }
    }

    private func describe(_ decision: AgentDecision) -> String {
        switch decision {
        case .allowOnce: return "allowed"
        case .allowForSession: return "allowed for the session"
        case .alwaysAllow: return "always allowed"
        case .deny: return "denied"
        case .noDecision: return "declined to decide on"
        }
    }

    // MARK: - Rules

    var approvalRules: [AgentApprovalRule] { ruleStore.allRules }

    func removeRule(id: UUID) { ruleStore.remove(id: id) }

    func removeAllRules() { ruleStore.removeAll() }

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

        refreshContext(for: event.sessionKey)
        scheduleSave()
    }

    // MARK: - Context window

    /// Reads a session's transcript tail and folds the result in.
    ///
    /// Throttled per session and done off the main actor: the transcript is
    /// megabytes and the notch must not wait on a file read.
    ///
    /// - Parameter force: skip the throttle, for an explicit user-visible refresh.
    func refreshContext(for sessionID: String, force: Bool = false) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard let path = sessions[index].transcriptPath, !path.isEmpty else { return }

        let now = Date()
        if !force, let last = lastContextReadAt[sessionID],
           now.timeIntervalSince(last) < Self.contextRefreshInterval {
            return
        }
        lastContextReadAt[sessionID] = now

        Task.detached(priority: .utility) {
            guard let snapshot = AgentTranscriptReader.read(path: path) else { return }
            await MainActor.run {
                AgentTowerManager.shared.applyTranscript(snapshot, to: sessionID)
            }
        }
    }

    private func applyTranscript(_ snapshot: AgentTranscriptSnapshot, to sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].apply(snapshot)
        scheduleSave()
    }

    /// Refreshes every live session. Called when the Agents tab appears, so a
    /// card the user is looking at is never stale.
    func refreshVisibleContexts() {
        for session in sessions where session.status != .idle {
            refreshContext(for: session.id, force: true)
        }
    }

    // MARK: - Terminal

    /// Brings a session's terminal forward.
    ///
    /// Best-effort by design: an exact tab where the terminal can be scripted,
    /// otherwise just the right application, which works everywhere and needs no
    /// automation consent.
    func jumpToTerminal(sessionID: String) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        Task { @MainActor in
            let outcome = await TerminalJumpService.jump(to: session)
            if outcome == .failed {
                Logger.log("Agent Tower: no terminal found for \(session.displayTitle)", category: .agents)
            }
        }
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
