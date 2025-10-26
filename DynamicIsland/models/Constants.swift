//
//  Constants.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 2024. 10. 17..
//  Modified by Hariharan Mudaliar

import SwiftUI
import Defaults
import Lottie

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

// MARK: - Custom Idle Animation Models
struct CustomIdleAnimation: Codable, Hashable, Equatable, Defaults.Serializable, Identifiable {
    let id: UUID
    var name: String
    var source: AnimationSource
    var speed: CGFloat = 1.0
    var isBuiltIn: Bool = false  // Track if it's bundled vs user-added
    
    init(id: UUID = UUID(), name: String, source: AnimationSource, speed: CGFloat = 1.0, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.speed = speed
        self.isBuiltIn = isBuiltIn
    }
    
    /// Get the effective transform config (override or default)
    func getTransformConfig() -> AnimationTransformConfig {
        let override = Defaults[.animationTransformOverrides][id.uuidString]
        if let override = override {
            print("📋 [CustomIdleAnimation] Found override for '\(name)': \(override)")
        } else {
            print("📋 [CustomIdleAnimation] No override for '\(name)', using default")
        }
        return override ?? .default
    }
}

struct AnimationTransformConfig: Codable, Hashable, Equatable, Defaults.Serializable {
    var scale: CGFloat = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var cropWidth: CGFloat = 30
    var cropHeight: CGFloat = 20
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1.0
    var paddingBottom: CGFloat = 0  // Allow adjustment to fill notch from bottom
    var expandWithAnimation: Bool = false  // Whether notch should expand horizontally with animation
    var loopMode: AnimationLoopMode = .loop  // Loop mode for animation
    
    static let `default` = AnimationTransformConfig()
}

enum AnimationLoopMode: String, Codable, CaseIterable {
    case loop = "Loop"
    case playOnce = "Play Once"
    case autoReverse = "Auto Reverse"
    
    var lottieLoopMode: LottieLoopMode {
        switch self {
        case .loop: return .loop
        case .playOnce: return .playOnce
        case .autoReverse: return .autoReverse
        }
    }
}

enum AnimationSource: Codable, Hashable, Equatable {
    case lottieFile(URL)        // Local file (in app support or bundle)
    case lottieURL(URL)         // Remote URL
    case builtInFace            // Original MinimalFaceFeatures
    
    var displayType: String {
        switch self {
        case .lottieFile: return "Local"
        case .lottieURL: return "Remote"
        case .builtInFace: return "Built-in"
        }
    }
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum ClipboardDisplayMode: String, CaseIterable, Codable, Defaults.Serializable {
    case popover = "popover"     // Traditional popover attached to button
    case panel = "panel"         // Floating panel near notch
    
    var displayName: String {
        switch self {
        case .popover: return "Popover"
        case .panel: return "Panel"
        }
    }
    
    var description: String {
        switch self {
        case .popover: return "Shows clipboard as a dropdown attached to the clipboard button"
        case .panel: return "Shows clipboard in a floating panel near the notch"
        }
    }
}

enum ScreenAssistantDisplayMode: String, CaseIterable, Codable, Defaults.Serializable {
    case popover = "popover"     // Traditional popover attached to button
    case panel = "panel"         // Floating panel near notch
    
    var displayName: String {
        switch self {
        case .popover: return "Popover"
        case .panel: return "Panel"
        }
    }
    
    var description: String {
        switch self {
        case .popover: return "Shows screen assistant as a dropdown attached to the AI button"
        case .panel: return "Shows screen assistant in a floating panel near the notch"
        }
    }
}

enum ColorPickerDisplayMode: String, CaseIterable, Codable, Defaults.Serializable {
    case popover = "popover"     // Traditional popover attached to button
    case panel = "panel"         // Floating panel near notch
    
    var displayName: String {
        switch self {
        case .popover: return "Popover"
        case .panel: return "Panel"
        }
    }
    
    var description: String {
        switch self {
        case .popover: return "Shows color picker as a dropdown attached to the color picker button"
        case .panel: return "Shows color picker in a floating panel near the notch"
        }
    }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "Youtube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

enum ProgressBarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"
    
    var id: String { self.rawValue }
}

// AI Model types for screen assistant
enum AIModelProvider: String, CaseIterable, Identifiable, Defaults.Serializable {
    case gemini = "Gemini"
    case openai = "OpenAI GPT"
    case claude = "Claude"
    case local = "Local Model"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        return self.rawValue
    }
    
    var description: String {
        switch self {
        case .gemini: return "Google's Gemini AI with multimodal capabilities"
        case .openai: return "OpenAI's GPT models with advanced reasoning"
        case .claude: return "Anthropic's Claude with strong analytical skills"
        case .local: return "Local AI model (Ollama or similar)"
        }
    }
    
    var supportedModels: [AIModel] {
        switch self {
        case .gemini:
            return [
                // Gemini 2.5 Models (Latest)
                AIModel(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", supportsThinking: true),
                AIModel(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", supportsThinking: true),
                AIModel(id: "gemini-2.5-flash-lite", name: "Gemini 2.5 Flash-Lite", supportsThinking: false),
                AIModel(id: "gemini-2.5-flash-live", name: "Gemini 2.5 Flash Live", supportsThinking: false),
                AIModel(id: "gemini-2.5-flash-native-audio", name: "Gemini 2.5 Flash Native Audio", supportsThinking: true),
                
                // Gemini 2.0 Models
                AIModel(id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", supportsThinking: false),
                AIModel(id: "gemini-2.0-flash-lite", name: "Gemini 2.0 Flash-Lite", supportsThinking: false),
                AIModel(id: "gemini-2.0-flash-live", name: "Gemini 2.0 Flash Live", supportsThinking: false),
                
                // Legacy 1.5 Models (for compatibility)
                AIModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", supportsThinking: false),
                AIModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", supportsThinking: false)
            ]
        case .openai:
            return [
                AIModel(id: "gpt-4o", name: "GPT-4o", supportsThinking: false),
                AIModel(id: "gpt-4o-mini", name: "GPT-4o Mini", supportsThinking: false),
                AIModel(id: "o1-preview", name: "o1 Preview", supportsThinking: true),
                AIModel(id: "o1-mini", name: "o1 Mini", supportsThinking: true)
            ]
        case .claude:
            return [
                AIModel(id: "claude-3-5-sonnet", name: "Claude 3.5 Sonnet", supportsThinking: false),
                AIModel(id: "claude-3-haiku", name: "Claude 3 Haiku", supportsThinking: false)
            ]
        case .local:
            return [
                AIModel(id: "llama3.2", name: "Llama 3.2", supportsThinking: false),
                AIModel(id: "qwen2.5", name: "Qwen 2.5", supportsThinking: false)
            ]
        }
    }
}

struct AIModel: Codable, Identifiable, Defaults.Serializable {
    let id: String
    let name: String
    let supportsThinking: Bool
    
    var displayName: String {
        return name + (supportsThinking ? " (Thinking)" : "")
    }
}

extension Defaults.Keys {
        // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "alpha 0.0.1")
    static let hidePanelsFromScreenCapture = Key<Bool>("hideFromScreenCapture", default: false)
    
        // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
	static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
        //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    
        // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
        //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let accentColor = Key<Color>("accentColor", default: Color.blue)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let useModernCloseAnimation = Key<Bool>("useModernCloseAnimation", default: true)
    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let customIdleAnimations = Key<[CustomIdleAnimation]>("customIdleAnimations", default: [])
    static let selectedIdleAnimation = Key<CustomIdleAnimation?>("selectedIdleAnimation", default: nil)
    static let animationTransformOverrides = Key<[String: AnimationTransformConfig]>("animationTransformOverrides", default: [:])
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
        // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
        // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let enableFullscreenMediaDetection = Key<Bool>("enableFullscreenMediaDetection", default: true)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let showMediaOutputControl = Key<Bool>("showMediaOutputControl", default: false)
    // Enable lock screen media widget (shows the standalone panel when screen is locked)
    static let enableLockScreenMediaWidget = Key<Bool>("enableLockScreenMediaWidget", default: true)
    static let enableLockScreenWeatherWidget = Key<Bool>("enableLockScreenWeatherWidget", default: true)
    static let lockScreenWeatherRefreshInterval = Key<TimeInterval>("lockScreenWeatherRefreshInterval", default: 30 * 60)
    static let lockScreenWeatherShowsLocation = Key<Bool>("lockScreenWeatherShowsLocation", default: true)
    static let lockScreenWeatherShowsCharging = Key<Bool>("lockScreenWeatherShowsCharging", default: true)
    static let lockScreenWeatherShowsBluetooth = Key<Bool>("lockScreenWeatherShowsBluetooth", default: true)
    static let lockScreenGlassStyle = Key<LockScreenGlassStyle>("lockScreenGlassStyle", default: .liquid)
    static let lockScreenShowAppIcon = Key<Bool>("lockScreenShowAppIcon", default: false)
    static let lockScreenPanelShowsBorder = Key<Bool>("lockScreenPanelShowsBorder", default: true)
    static let lockScreenPanelUsesBlur = Key<Bool>("lockScreenPanelUsesBlur", default: true)
    
        // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
        // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
        // MARK: HUD
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let progressBarStyle = Key<ProgressBarStyle>("progressBarStyle", default: .hierarchical)
    // Legacy support - keeping for backward compatibility
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showProgressPercentages = Key<Bool>("showProgressPercentages", default: false)
    
        // MARK: Shelf
    static let dynamicShelf = Key<Bool>("dynamicShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    
        // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    
        // MARK: Fullscreen Media Detection
    static let alwaysHideInFullscreen = Key<Bool>("alwaysHideInFullscreen", default: false)
    
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Wobble Animation
    static let enableWobbleAnimation = Key<Bool>("enableWobbleAnimation", default: false)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Bluetooth Audio Devices
    static let showBluetoothDeviceConnections = Key<Bool>("showBluetoothDeviceConnections", default: true)
    static let useColorCodedBatteryDisplay = Key<Bool>("useColorCodedBatteryDisplay", default: true)
    static let useColorCodedVolumeDisplay = Key<Bool>("useColorCodedVolumeDisplay", default: false)
    static let useSmoothColorGradient = Key<Bool>("useSmoothColorGradient", default: true)
    
    // MARK: Stats Feature
    static let enableStatsFeature = Key<Bool>("enableStatsFeature", default: false)
    static let autoStartStatsMonitoring = Key<Bool>("autoStartStatsMonitoring", default: true)
    static let showCpuGraph = Key<Bool>("showCpuGraph", default: true)
    static let showMemoryGraph = Key<Bool>("showMemoryGraph", default: true)
    static let showGpuGraph = Key<Bool>("showGpuGraph", default: true)
    static let showNetworkGraph = Key<Bool>("showNetworkGraph", default: false)
    static let showDiskGraph = Key<Bool>("showDiskGraph", default: false)
    static let showStatsPanel = Key<Bool>("showStatsPanel", default: true)
    
    // MARK: Timer Feature
    static let enableTimerFeature = Key<Bool>("enableTimerFeature", default: true)
    
    // MARK: ColorPicker Feature
    static let enableColorPickerFeature = Key<Bool>("enableColorPickerFeature", default: true)
    static let showColorFormats = Key<Bool>("showColorFormats", default: true)
    static let colorPickerDisplayMode = Key<ColorPickerDisplayMode>("colorPickerDisplayMode", default: .panel)
    static let colorHistorySize = Key<Int>("colorHistorySize", default: 10)
    static let showColorPickerIcon = Key<Bool>("showColorPickerIcon", default: true)
    
    // MARK: Clipboard Feature
    static let enableClipboardManager = Key<Bool>("enableClipboardManager", default: true)
    static let clipboardHistorySize = Key<Int>("clipboardHistorySize", default: 3)
    static let showClipboardIcon = Key<Bool>("showClipboardIcon", default: true)
    static let clipboardDisplayMode = Key<ClipboardDisplayMode>("clipboardDisplayMode", default: .panel)
    
    // MARK: Screen Assistant Feature
    static let enableScreenAssistant = Key<Bool>("enableScreenAssistant", default: true)
    static let screenAssistantDisplayMode = Key<ScreenAssistantDisplayMode>("screenAssistantDisplayMode", default: .panel)
    static let geminiApiKey = Key<String>("geminiApiKey", default: "")
    static let openaiApiKey = Key<String>("openaiApiKey", default: "")
    static let claudeApiKey = Key<String>("claudeApiKey", default: "")
    static let selectedAIProvider = Key<AIModelProvider>("selectedAIProvider", default: .gemini)
    static let selectedAIModel = Key<AIModel?>("selectedAIModel", default: nil)
    static let enableThinkingMode = Key<Bool>("enableThinkingMode", default: false)
    static let localModelEndpoint = Key<String>("localModelEndpoint", default: "http://localhost:11434")
    
    // MARK: Keyboard Shortcuts
    static let enableShortcuts = Key<Bool>("enableShortcuts", default: true)
    
    // MARK: System HUD Feature
    static let enableSystemHUD = Key<Bool>("enableSystemHUD", default: false)
    static let enableVolumeHUD = Key<Bool>("enableVolumeHUD", default: true)
    static let enableBrightnessHUD = Key<Bool>("enableBrightnessHUD", default: true)
    static let enableKeyboardBacklightHUD = Key<Bool>("enableKeyboardBacklightHUD", default: true)
    static let systemHUDSensitivity = Key<Int>("systemHUDSensitivity", default: 5)
    
    // MARK: Screen Recording Detection Feature
    static let enableScreenRecordingDetection = Key<Bool>("enableScreenRecordingDetection", default: true)
    static let showRecordingIndicator = Key<Bool>("showRecordingIndicator", default: true)
    // Polling removed - now uses event-driven private API detection (CGSIsScreenWatcherPresent)
    // static let enableScreenRecordingPolling = Key<Bool>("enableScreenRecordingPolling", default: false)
    
    // MARK: Privacy Indicators (Camera & Microphone Detection)
    static let enableCameraDetection = Key<Bool>("enableCameraDetection", default: true)
    static let enableMicrophoneDetection = Key<Bool>("enableMicrophoneDetection", default: true)
    
    // MARK: Lock Screen Features
    static let enableLockScreenLiveActivity = Key<Bool>("enableLockScreenLiveActivity", default: true)
    
    // MARK: ImageService
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCacheV1", default: false)
    
    // MARK: Minimalistic UI Mode
    static let enableMinimalisticUI = Key<Bool>("enableMinimalisticUI", default: false)
    
    // Helper to determine the default media controller based on macOS version
    static var defaultMediaController: MediaControllerType {
        if #available(macOS 15.4, *) {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }
    
    // Migration helper to convert from legacy enableGradient Boolean to new ProgressBarStyle enum
    static func migrateProgressBarStyle() {
        // Check if migration is needed by seeing if the old Boolean was set to gradient
        let wasGradientEnabled = Defaults[.enableGradient]
        
        // Only migrate if we're still using the default hierarchical value but gradient was enabled
        if wasGradientEnabled && Defaults[.progressBarStyle] == .hierarchical {
            Defaults[.progressBarStyle] = .gradient
        }
    }
}
