import CodeIslandCore
import Foundation

/// Codex lifecycle events proposed by the Phase 4 installation machinery.
///
/// Activation remains unavailable until Phase 5 verifies the complete bridge
/// and listener path for each event.
public enum CodexManagedHookEvent: String, Codable, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"

    public static let phaseFourMonitoringEvents: [CodexManagedHookEvent] = [
        .sessionStart,
        .sessionEnd,
        .userPromptSubmit,
        .preToolUse,
        .postToolUse,
        .permissionRequest,
        .stop,
    ]
}

/// A one-plan, one-provider confirmation token created after user consent.
public struct CodeIslandActivationConsent: Equatable, Sendable {
    let planID: UUID
    let provider: AgentProvider

    init(planID: UUID, provider: AgentProvider) {
        self.planID = planID
        self.provider = provider
    }
}

/// Durable ownership information returned by a successful managed install.
public struct CodeIslandManagedInstallationReceipt: Codable, Equatable, Sendable {
    public let planID: UUID
    public let provider: AgentProvider
    public let hookConfigurationURL: URL
    public let managedBridgeURL: URL
    public let managedReceiptURL: URL
    public let managedCommand: String
    public let hookEvents: [CodexManagedHookEvent]
    public let bridgeDigest: String
    public let createdHookConfiguration: Bool
    public let createdManagedBridge: Bool

    public init(
        planID: UUID,
        provider: AgentProvider,
        hookConfigurationURL: URL,
        managedBridgeURL: URL,
        managedReceiptURL: URL,
        managedCommand: String,
        hookEvents: [CodexManagedHookEvent],
        bridgeDigest: String,
        createdHookConfiguration: Bool = false,
        createdManagedBridge: Bool = false
    ) {
        self.planID = planID
        self.provider = provider
        self.hookConfigurationURL = hookConfigurationURL
        self.managedBridgeURL = managedBridgeURL
        self.managedReceiptURL = managedReceiptURL
        self.managedCommand = managedCommand
        self.hookEvents = hookEvents
        self.bridgeDigest = bridgeDigest
        self.createdHookConfiguration = createdHookConfiguration
        self.createdManagedBridge = createdManagedBridge
    }
}

/// Typed activation failures that occur before an operating-system adapter fails.
public enum CodeIslandActivationError: Error, Equatable {
    case consentRequired
    case staleConsent
    case blocked(Set<CodeIslandAdoptionBlocker>)
    case invalidPlan
    case alreadyActive
    case notActive
}

/// Last-moment, read-only safety check performed after consent and before bind.
public protocol CodeIslandActivationPreflighting {
    func validate(plan: CodeIslandInstallationPlan) throws
}

/// Listener lifecycle boundary. Its start method must return only when ready.
public protocol CodeIslandListenerControlling {
    func start(at socketURL: URL) throws
    func enterPassThrough()
    func drain(timeout: TimeInterval)
    func stop()
}

/// Provider-configuration boundary. A throwing install must roll back its writes.
public protocol CodeIslandManagedInstalling {
    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt
    func verify(receipt: CodeIslandManagedInstallationReceipt) throws
    func remove(receipt: CodeIslandManagedInstallationReceipt) throws
}

/// Orders one explicit activation transaction across its system boundaries.
///
/// The Atoll host owns this coordinator on one serialized execution context.
/// It deliberately has no default live adapters while provider rollout remains
/// gated in Phase 4.
public final class CodeIslandActivationCoordinator {
    private let preflight: any CodeIslandActivationPreflighting
    private let listener: any CodeIslandListenerControlling
    private let installer: any CodeIslandManagedInstalling
    private let drainTimeout: TimeInterval
    private var activeReceipt: CodeIslandManagedInstallationReceipt?

    public init(
        preflight: any CodeIslandActivationPreflighting,
        listener: any CodeIslandListenerControlling,
        installer: any CodeIslandManagedInstalling,
        drainTimeout: TimeInterval = 1
    ) {
        self.preflight = preflight
        self.listener = listener
        self.installer = installer
        self.drainTimeout = max(0, drainTimeout)
    }

    /// Starts the ready listener before any provider hook is installed.
    public func activate(
        plan: CodeIslandInstallationPlan,
        consent: CodeIslandActivationConsent?
    ) throws -> CodeIslandManagedInstallationReceipt {
        guard activeReceipt == nil else { throw CodeIslandActivationError.alreadyActive }
        guard let consent else { throw CodeIslandActivationError.consentRequired }
        guard consent.planID == plan.id, consent.provider == plan.provider else {
            throw CodeIslandActivationError.staleConsent
        }
        guard plan.blockers.isEmpty else {
            throw CodeIslandActivationError.blocked(plan.blockers)
        }
        guard let socketURL = plan.listenerSocketURL else {
            throw CodeIslandActivationError.invalidPlan
        }

        try preflight.validate(plan: plan)
        try listener.start(at: socketURL)

        var installedReceipt: CodeIslandManagedInstallationReceipt?
        do {
            let receipt = try installer.install(plan: plan)
            installedReceipt = receipt
            try installer.verify(receipt: receipt)
            activeReceipt = receipt
            return receipt
        } catch {
            listener.enterPassThrough()
            if let installedReceipt {
                try? installer.remove(receipt: installedReceipt)
            }
            listener.drain(timeout: drainTimeout)
            listener.stop()
            throw error
        }
    }

    /// Enters pass-through before removing only the receipt-owned installation.
    public func deactivate(receipt: CodeIslandManagedInstallationReceipt) throws {
        guard activeReceipt == receipt else { throw CodeIslandActivationError.notActive }
        listener.enterPassThrough()
        try installer.remove(receipt: receipt)
        listener.drain(timeout: drainTimeout)
        listener.stop()
        activeReceipt = nil
    }
}

private extension CodeIslandInstallationPlan {
    var listenerSocketURL: URL? {
        let socketKinds: Set<CodeIslandConfigurationChangeKind> = [
            .createListenerSocket,
            .replaceStaleListenerSocket,
            .resolveLegacySocketConflict,
        ]
        let matches = changes.filter { socketKinds.contains($0.kind) }
        guard matches.count == 1 else { return nil }
        return matches[0].url
    }
}
