import AppKit
import Combine
import Sparkle
import os.log

/// Simplified update state surfaced to the About page. Sparkle handles the
/// actual download / install UX itself — we only mirror enough state to drive
/// the little banner at the bottom of the About page.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed(String)
}

@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    static let shared = UpdateChecker()
    private static let log = Logger(subsystem: "com.codeisland", category: "UpdateChecker")

    @Published private(set) var state: UpdateState = .idle

    private lazy var controller: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    /// Exposed for advanced integrations (menu bindings etc.); prefer
    /// `checkForUpdates()` and `state` for most UI.
    var updater: SPUUpdater { controller.updater }

    /// True when the app bundle lives inside a Homebrew cask path. Homebrew
    /// manages its own upgrade flow, so Sparkle stays hands-off in that case.
    var isHomebrewInstall: Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/Caskroom/") || path.contains("/homebrew/")
    }

    // MARK: - Lifecycle

    /// Wire up Sparkle. Call once from `AppDelegate.applicationDidFinishLaunching`.
    func start() {
        #if DEBUG
        // Sparkle crashes if we run without a proper Bundle ID (e.g. raw executable via Xcode/SPM)
        if Bundle.main.bundleIdentifier == nil {
            Self.log.info("No Bundle ID detected in DEBUG mode — skipping Sparkle")
            return
        }
        #endif

        if isHomebrewInstall {
            Self.log.info("Homebrew install detected — disabling Sparkle auto-checks")
            updater.automaticallyChecksForUpdates = false
        } else {
            updater.automaticallyChecksForUpdates = true
        }
        controller.startUpdater()
    }

    // MARK: - Public API (mirrors the pre-Sparkle signature for call-site compat)

    /// User-initiated check. Sparkle presents its own progress / prompt UI.
    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        state = .checking
        controller.checkForUpdates(nil)
    }

    /// Legacy entry point kept so existing call sites continue to compile.
    /// Sparkle drives the install flow from the `didFindValidUpdate` alert, so
    /// this just re-surfaces that alert if the user dismissed it.
    func performUpdate() {
        checkForUpdates()
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    // Sparkle dispatches delegate callbacks on an arbitrary queue; hop back
    // onto the main actor before touching @Published state.

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.state = .available(version: version)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.state = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let description = error.localizedDescription
        Task { @MainActor in
            Self.log.debug("Sparkle aborted: \(description)")
            if self.state == .checking {
                self.state = .failed(description)
            }
        }
    }
}
