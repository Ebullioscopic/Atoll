import Foundation
import Combine
import Defaults

// ManagerRegistry
// Lazy-loads feature managers based on Defaults toggle state.
// Core managers (DynamicIslandViewCoordinator, ExtensionRPCServer,
// ExtensionXPCServiceHost, DoNotDisturbManager, MediaControlsStateCoordinator)
// are always active and are NOT managed here.

final class ManagerRegistry {

    static let shared = ManagerRegistry()

    // MARK: - Managed manager instances (nil = disabled / deinit'd)

    private(set) var statsManager: StatsManager?
    private(set) var timerManager: TimerManager?
    private(set) var downloadManager: DownloadManager?
    private(set) var notificationManager: NotificationManager?
    private(set) var batteryActivityManager: BatteryActivityManager?
    private(set) var agentStatusManager: AgentStatusManager?
    private(set) var extensionLiveActivityManager: ExtensionLiveActivityManager?
    private(set) var extensionNotchExperienceManager: ExtensionNotchExperienceManager?
    private(set) var lockScreenManager: LockScreenManager?
    private(set) var lockScreenWeatherManager: LockScreenWeatherManager?
    private(set) var webcamManager: WebcamManager?
    private(set) var bluetoothAudioManager: BluetoothAudioManager?

    // MARK: - Combine

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    private init() {
        setupObservers()
    }

    // MARK: - Observer Setup

    private func setupObservers() {
        // Perform an initial activation pass based on current toggle state,
        // then subscribe to future changes.

        observe(.enableStatsFeature) { [weak self] enabled in
            if enabled {
                if self?.statsManager == nil { self?.statsManager = StatsManager.shared }
            } else {
                self?.statsManager = nil
            }
        }

        observe(.enableTimerFeature) { [weak self] enabled in
            if enabled {
                if self?.timerManager == nil { self?.timerManager = TimerManager.shared }
            } else {
                self?.timerManager = nil
            }
        }

        observe(.enableDownloadListener) { [weak self] enabled in
            if enabled {
                if self?.downloadManager == nil { self?.downloadManager = DownloadManager.shared }
            } else {
                self?.downloadManager = nil
            }
        }

        observe(.enableMessageNotifications) { [weak self] enabled in
            if enabled {
                if self?.notificationManager == nil { self?.notificationManager = NotificationManager.shared }
            } else {
                self?.notificationManager = nil
            }
        }

        observe(.showBatteryIndicator) { [weak self] enabled in
            if enabled {
                if self?.batteryActivityManager == nil { self?.batteryActivityManager = BatteryActivityManager.shared }
            } else {
                self?.batteryActivityManager = nil
            }
        }

        observe(.enableAgentStatus) { [weak self] enabled in
            if enabled {
                if self?.agentStatusManager == nil { self?.agentStatusManager = AgentStatusManager.shared }
            } else {
                self?.agentStatusManager = nil
            }
        }

        observe(.enableExtensionLiveActivities) { [weak self] enabled in
            if enabled {
                if self?.extensionLiveActivityManager == nil {
                    self?.extensionLiveActivityManager = ExtensionLiveActivityManager.shared
                }
            } else {
                self?.extensionLiveActivityManager = nil
            }
        }

        observe(.enableExtensionNotchExperiences) { [weak self] enabled in
            if enabled {
                if self?.extensionNotchExperienceManager == nil {
                    self?.extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
                }
            } else {
                self?.extensionNotchExperienceManager = nil
            }
        }

        observe(.enableLockScreenMediaWidget) { [weak self] enabled in
            if enabled {
                if self?.lockScreenManager == nil { self?.lockScreenManager = LockScreenManager.shared }
            } else {
                self?.lockScreenManager = nil
            }
        }

        observe(.enableLockScreenWeatherWidget) { [weak self] enabled in
            if enabled {
                if self?.lockScreenWeatherManager == nil {
                    self?.lockScreenWeatherManager = LockScreenWeatherManager.shared
                }
            } else {
                self?.lockScreenWeatherManager = nil
            }
        }

        observe(.showMirror) { [weak self] enabled in
            if enabled {
                if self?.webcamManager == nil { self?.webcamManager = WebcamManager.shared }
            } else {
                self?.webcamManager = nil
            }
        }

        observe(.showBluetoothDeviceConnections) { [weak self] enabled in
            if enabled {
                if self?.bluetoothAudioManager == nil {
                    self?.bluetoothAudioManager = BluetoothAudioManager.shared
                }
            } else {
                self?.bluetoothAudioManager = nil
            }
        }
    }

    // MARK: - Helpers

    /// Subscribes to a Defaults key, fires immediately with the current value,
    /// then fires again on every subsequent change.
    private func observe(_ key: Defaults.Key<Bool>, handler: @escaping (Bool) -> Void) {
        // Emit the current value immediately so the initial activation pass
        // runs in the same call as the subscription setup.
        handler(Defaults[key])
        Defaults.publisher(key)
            .map(\.newValue)
            .receive(on: DispatchQueue.main)
            .sink { handler($0) }
            .store(in: &cancellables)
    }

    // MARK: - Preset: Beacon Mode

    /// Configures the app for beacon/kiosk mode.
    /// All feature toggles are disabled except the agent-status and extension
    /// features, plus the core UI controls needed for the notch experience.
    func activateBeaconMode() {
        // Disable all managed feature toggles first
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = false
        Defaults[.enableDownloadListener] = false
        Defaults[.enableSneakPeek] = false
        Defaults[.enableMessageNotifications] = false
        Defaults[.showBatteryIndicator] = false
        Defaults[.enableTerminalFeature] = false
        Defaults[.enableLockScreenMediaWidget] = false
        Defaults[.enableLockScreenWeatherWidget] = false
        Defaults[.showMirror] = false
        Defaults[.showBluetoothDeviceConnections] = false

        // Enable beacon-relevant features
        Defaults[.enableAgentStatus] = true
        Defaults[.enableExtensionNotchExperiences] = true
        Defaults[.enableExtensionLiveActivities] = true

        // Keep core UI toggles active
        Defaults[.menubarIcon] = true
        Defaults[.openNotchOnHover] = true
        Defaults[.enableHaptics] = true
    }

    // MARK: - Preset: Restore Defaults

    /// Resets all managed feature toggles to their compiled-in default values.
    func restoreDefaults() {
        Defaults.reset(
            .enableStatsFeature,
            .enableTimerFeature,
            .enableDownloadListener,
            .enableSneakPeek,
            .enableMessageNotifications,
            .showBatteryIndicator,
            .enableTerminalFeature,
            .enableAgentStatus,
            .enableExtensionLiveActivities,
            .enableExtensionNotchExperiences,
            .enableLockScreenMediaWidget,
            .enableLockScreenWeatherWidget,
            .showMirror,
            .showBluetoothDeviceConnections,
            .menubarIcon,
            .openNotchOnHover,
            .enableHaptics
        )
    }
}
