import Darwin
import Foundation

/// Safety failures found after consent but before listener startup.
public enum CodeIslandActivationPreflightError: Error, Equatable {
    case invalidPlan
    case legacyApplicationRunning
    case legacySocketOccupied
    case legacySocketPathUnsafe
    case socketStateChanged
    case staleSocketNotOwnedByCurrentUser
    case staleSocketChanged
    case staleSocketRemovalFailed
}

/// Mutation boundary limited to reclaiming one disclosed, stale socket path.
public protocol CodeIslandStaleSocketReclaiming {
    func reclaimStaleSocket(at socketURL: URL) throws
}

/// Revalidates socket type, owner, identity, and staleness immediately before unlink.
public struct CodeIslandSystemStaleSocketReclaimer: CodeIslandStaleSocketReclaiming {
    private let inspector: any CodeIslandSocketInspecting

    public init(
        inspector: any CodeIslandSocketInspecting = CodeIslandSystemSocketInspector()
    ) {
        self.inspector = inspector
    }

    public func reclaimStaleSocket(at socketURL: URL) throws {
        guard inspector.state(at: socketURL) == .stale else {
            throw CodeIslandActivationPreflightError.staleSocketChanged
        }

        var first = stat()
        guard lstat(socketURL.path, &first) == 0,
              first.st_mode & S_IFMT == S_IFSOCK else {
            throw CodeIslandActivationPreflightError.legacySocketPathUnsafe
        }
        guard first.st_uid == getuid() else {
            throw CodeIslandActivationPreflightError.staleSocketNotOwnedByCurrentUser
        }

        var second = stat()
        guard lstat(socketURL.path, &second) == 0,
              second.st_dev == first.st_dev,
              second.st_ino == first.st_ino,
              second.st_uid == first.st_uid,
              second.st_mode & S_IFMT == S_IFSOCK,
              inspector.state(at: socketURL) == .stale else {
            throw CodeIslandActivationPreflightError.staleSocketChanged
        }
        guard Darwin.unlink(socketURL.path) == 0 else {
            throw CodeIslandActivationPreflightError.staleSocketRemovalFailed
        }
    }
}

/// Rechecks standalone-app and socket ownership at the activation boundary.
///
/// A stale socket is reclaimed only when that exact mutation was disclosed in
/// the consented plan. Active, inaccessible, foreign, and unexpected paths are
/// never removed.
public struct CodeIslandAdoptionPreflight: CodeIslandActivationPreflighting {
    private let socketInspector: any CodeIslandSocketInspecting
    private let applicationInspector: any CodeIslandLegacyApplicationInspecting
    private let staleSocketReclaimer: any CodeIslandStaleSocketReclaiming

    public init(
        socketInspector: any CodeIslandSocketInspecting = CodeIslandSystemSocketInspector(),
        applicationInspector: any CodeIslandLegacyApplicationInspecting = CodeIslandSystemApplicationInspector(),
        staleSocketReclaimer: any CodeIslandStaleSocketReclaiming = CodeIslandSystemStaleSocketReclaimer()
    ) {
        self.socketInspector = socketInspector
        self.applicationInspector = applicationInspector
        self.staleSocketReclaimer = staleSocketReclaimer
    }

    public func validate(plan: CodeIslandInstallationPlan) throws {
        guard !applicationInspector.isApplicationRunning(
            bundleIdentifier: "com.codeisland.app"
        ) else {
            throw CodeIslandActivationPreflightError.legacyApplicationRunning
        }

        let socketKinds: Set<CodeIslandConfigurationChangeKind> = [
            .createListenerSocket,
            .replaceStaleListenerSocket,
            .resolveLegacySocketConflict,
        ]
        let socketChanges = plan.changes.filter { socketKinds.contains($0.kind) }
        guard socketChanges.count == 1 else {
            throw CodeIslandActivationPreflightError.invalidPlan
        }
        let change = socketChanges[0]
        let state = socketInspector.state(at: change.url)

        switch state {
        case .occupied:
            throw CodeIslandActivationPreflightError.legacySocketOccupied
        case .unexpectedFile, .inaccessible:
            throw CodeIslandActivationPreflightError.legacySocketPathUnsafe
        case .absent:
            guard change.kind == .createListenerSocket else {
                throw CodeIslandActivationPreflightError.socketStateChanged
            }
        case .stale:
            guard change.kind == .replaceStaleListenerSocket else {
                throw CodeIslandActivationPreflightError.socketStateChanged
            }
            try staleSocketReclaimer.reclaimStaleSocket(at: change.url)
        }
    }
}
