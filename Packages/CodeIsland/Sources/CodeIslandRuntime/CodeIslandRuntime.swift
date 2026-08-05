import CodeIslandCore
import Foundation

/// Observable lifecycle of the provider runtime, independent of Atoll views.
public enum CodeIslandRuntimeState: Equatable, Sendable {
    case inactive
    case active(provider: AgentProvider)
}

/// Atoll-owned Code Island runtime boundary.
///
/// This deep module owns activation ordering, receipt-based restart, sanitized
/// projection, metadata persistence, and bounded shutdown. Callers never touch
/// the listener or hook installer directly.
public final class CodeIslandRuntime: @unchecked Sendable {
    /// Code Island never activates a provider without explicit user consent.
    public static let isEnabledByDefault = false

    private let lock = NSLock()
    private let coordinator: CodeIslandActivationCoordinator
    private let metadataStore: any SessionMetadataStoring
    private let projector = SessionMetadataProjector()
    private let onSessionProjection: @Sendable (SessionMetadata, SessionMetadata?) -> Void
    private var runtimeState: CodeIslandRuntimeState = .inactive
    private var projections: [String: SessionMetadata]

    public var state: CodeIslandRuntimeState {
        lock.lock()
        defer { lock.unlock() }
        return runtimeState
    }

    /// Whether a verified provider listener is currently active.
    public var isRunning: Bool {
        if case .active = state { return true }
        return false
    }

    /// Current metadata-only projections in deterministic provider/session order.
    public var sessions: [SessionMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return sortedSessions(Array(projections.values))
    }

    public init(
        coordinator: CodeIslandActivationCoordinator,
        metadataStore: any SessionMetadataStoring,
        onSessionProjection: @escaping @Sendable (SessionMetadata, SessionMetadata?) -> Void = { _, _ in }
    ) {
        self.coordinator = coordinator
        self.metadataStore = metadataStore
        self.onSessionProjection = onSessionProjection
        let loaded = (try? metadataStore.load()) ?? []
        projections = Dictionary(
            loaded.map { (Self.key(provider: $0.provider, sessionID: $0.sessionID), $0) },
            uniquingKeysWith: { current, latest in
                latest.updatedAt >= current.updatedAt ? latest : current
            }
        )
    }

    /// Creates an inert runtime for previews and hosts that have not selected
    /// the Phase 5 live adapter factory.
    public convenience init() {
        self.init(
            coordinator: CodeIslandActivationCoordinator(
                preflight: InertPreflight(),
                listener: InertListener(),
                installer: InertInstaller()
            ),
            metadataStore: InMemoryMetadataStore()
        )
    }

    /// Constructs the production adapters without starting or mutating them.
    public static func live(
        paths: CodeIslandDiscoveryPaths = .live(),
        onSessionProjection: @escaping @Sendable (SessionMetadata, SessionMetadata?) -> Void = { _, _ in }
    ) -> CodeIslandRuntime {
        let sink = RuntimeObservationSink()
        let listener = CodeIslandUnixObservationListener { observation in
            sink.receive(observation)
        }
        let managedRoot = paths.managedReceiptURL.deletingLastPathComponent()
        let coordinator = CodeIslandActivationCoordinator(
            preflight: CodeIslandAdoptionPreflight(),
            listener: listener,
            installer: CodexManagedInstallation(managedRootURL: managedRoot)
        )
        let runtime = CodeIslandRuntime(
            coordinator: coordinator,
            metadataStore: FileSessionMetadataStore(
                fileURL: managedRoot.appendingPathComponent("sessions.json")
            ),
            onSessionProjection: onSessionProjection
        )
        sink.runtime = runtime
        return runtime
    }

    /// Resumes only an installation proven by Atoll's durable receipt.
    public func start(plan: CodeIslandInstallationPlan) throws {
        let receipt = try coordinator.resume(plan: plan)
        lock.lock()
        runtimeState = receipt.map { .active(provider: $0.provider) } ?? .inactive
        lock.unlock()
    }

    /// Activates one consented provider transaction.
    @discardableResult
    public func activate(
        plan: CodeIslandInstallationPlan,
        consent: CodeIslandActivationConsent?
    ) throws -> CodeIslandManagedInstallationReceipt {
        let receipt = try coordinator.activate(plan: plan, consent: consent)
        lock.lock()
        runtimeState = .active(provider: receipt.provider)
        lock.unlock()
        return receipt
    }

    /// Removes only the active receipt-owned provider installation.
    public func deactivate() throws {
        guard let receipt = coordinator.activeReceipt else {
            throw CodeIslandActivationError.notActive
        }
        try coordinator.deactivate(receipt: receipt)
        lock.lock()
        runtimeState = .inactive
        lock.unlock()
    }

    /// Repairs only the already-active receipt-owned provider integration.
    public func repair(plan: CodeIslandInstallationPlan) throws {
        let receipt = try coordinator.repairActive(plan: plan)
        lock.lock()
        runtimeState = .active(provider: receipt.provider)
        lock.unlock()
    }

    /// Accepts the already-sanitized listener seam and publishes its projection.
    public func receive(_ observation: SessionObservation) {
        let key = Self.key(provider: observation.provider, sessionID: observation.sessionID)
        lock.lock()
        guard case .active = runtimeState else {
            lock.unlock()
            return
        }
        let previous = projections[key]
        let current = projector.applying(observation, to: previous)
        projections[key] = current
        let allSessions = sortedSessions(Array(projections.values))
        try? metadataStore.save(allSessions)
        lock.unlock()
        onSessionProjection(current, previous)
    }

    /// Applies Atoll's retention preference to terminal metadata. Active
    /// sessions are never removed. If the archive cannot be replaced, the
    /// in-memory projection is left unchanged so both views stay consistent.
    @discardableResult
    public func applyRetentionPolicy(
        retentionMinutes: Int,
        now: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let current = sortedSessions(Array(projections.values))
        let retained = SessionMetadataRetentionPolicy(
            retentionMinutes: retentionMinutes
        ).retainedSessions(from: current, now: now)
        guard retained != current else { return true }
        do {
            try metadataStore.save(retained)
        } catch {
            return false
        }

        projections = Dictionary(
            uniqueKeysWithValues: retained.map {
                (Self.key(provider: $0.provider, sessionID: $0.sessionID), $0)
            }
        )
        return true
    }

    /// Enters pass-through, drains bounded work, and stops without uninstalling.
    public func shutdown() {
        coordinator.shutdown()
        lock.lock()
        runtimeState = .inactive
        lock.unlock()
    }

    private static func key(provider: AgentProvider, sessionID: OpaqueSessionID) -> String {
        "\(provider.rawValue):\(sessionID.rawValue)"
    }

    private func sortedSessions(_ sessions: [SessionMetadata]) -> [SessionMetadata] {
        sessions.sorted {
            if $0.provider.rawValue != $1.provider.rawValue {
                return $0.provider.rawValue < $1.provider.rawValue
            }
            return $0.sessionID.rawValue < $1.sessionID.rawValue
        }
    }
}

private final class RuntimeObservationSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storedRuntime: CodeIslandRuntime?

    var runtime: CodeIslandRuntime? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedRuntime
        }
        set {
            lock.lock()
            storedRuntime = newValue
            lock.unlock()
        }
    }

    func receive(_ observation: SessionObservation) {
        runtime?.receive(observation)
    }
}

private struct InertPreflight: CodeIslandActivationPreflighting {
    func validate(plan: CodeIslandInstallationPlan) throws {}
}

private struct InertListener: CodeIslandListenerControlling {
    func start(at socketURL: URL) throws {}
    func enterPassThrough() {}
    func drain(timeout: TimeInterval) {}
    func stop() {}
}

private struct InertInstaller: CodeIslandManagedInstalling {
    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt {
        throw CodeIslandActivationError.invalidPlan
    }
    func verify(receipt: CodeIslandManagedInstallationReceipt) throws {}
    func remove(receipt: CodeIslandManagedInstallationReceipt) throws {}
}

private final class InMemoryMetadataStore: SessionMetadataStoring, @unchecked Sendable {
    private var sessions: [SessionMetadata] = []
    func load() throws -> [SessionMetadata] { sessions }
    func save(_ sessions: [SessionMetadata]) throws { self.sessions = sessions }
}
