//
//  MusicManager.swift
//  DynamicIsland
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    
    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?
    
    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var lastUpdated: Date = .distantPast
    @Published var ignoreLastUpdated = true
    @Published var isPlayerIdle: Bool = true
    @Published var animations: DynamicIslandAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    
    private var artworkData: Data? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()
        
        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if let _ = activeController {
            controllerCancellables.removeAll()
            activeController = nil
        }
        
        let newController: (any MediaControllerProtocol)?
        
        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                ignoreLastUpdated = false
                if let controller = NowPlayingController() {
                    // Check if the controller can actually work
                    if controller.isWorking {
                        newController = controller
                    } else {
                        print("⚠️ NowPlayingController created but resources unavailable, falling back to default")
                        return nil
                    }
                } else {
                    return nil
                }
            } else {
                return nil
            }
        case .appleMusic:
            ignoreLastUpdated = true
            newController = AppleMusicController()
        case .spotify:
            ignoreLastUpdated = true
            newController = SpotifyController()
        case .youtubeMusic:
            ignoreLastUpdated = true
            newController = YouTubeMusicController()
        }
        
        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }
        
        return newController
    }
    
    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")
        
        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType
        
        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }
    }
    
    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Transition animation when changing controllers
        transitionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isTransitioning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.isTransitioning = false
            }
        }
        transitionWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
        
        // Set new active controller
        activeController = controller
        
        // Get current state from active controller
        if let state = Mirror(reflecting: controller).children.first(where: { $0.label == "playbackState" })?.value as? PlaybackState {
            updateFromPlaybackState(state)
        }
    }

    // MARK: - Update Methods
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Create a batch of updates to apply together
        let updateBatch = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Check for playback state changes (playing/paused)
            if state.isPlaying != self.isPlaying {
                self.lastUpdated = Date()
                withAnimation(.smooth) {
                    self.isPlaying = state.isPlaying
                    self.updateIdleState(state: state.isPlaying)
                }
                
                if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                    self.updateSneakPeek()
                }
            }
            
            // Check for changes in track metadata
            let titleChanged = state.title != self.songTitle
            let artistChanged = state.artist != self.artistName
            let albumChanged = state.album != self.album
            
            // Check for artwork changes
            let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
            let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged
            
            // Handle artwork and visual transitions for changed content
            if hasContentChange {
                self.triggerFlipAnimation()
                
                if artworkChanged, let artwork = state.artwork {
                    self.updateArtwork(artwork)
                } else if hasContentChange && state.artwork == nil {
                    // Try to use app icon if no artwork but track changed
                    if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                        self.usingAppIconForArtwork = true
                        self.updateAlbumArt(newAlbumArt: appIconImage)
                    }
                }
                self.artworkData = state.artwork
                
                // Only update sneak peek if there's actual content and something changed
                if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                    self.updateSneakPeek()
                }
            }
            
            let timeChanged = state.currentTime != self.elapsedTime
            let durationChanged = state.duration != self.songDuration
            let playbackRateChanged = state.playbackRate != self.playbackRate
            
            if titleChanged {
                self.songTitle = state.title
            }
            
            if artistChanged {
                self.artistName = state.artist
            }
            
            if albumChanged {
                self.album = state.album
            }
            
            if timeChanged {
                self.elapsedTime = state.currentTime
            }
            
            if durationChanged {
                self.songDuration = state.duration
            }
            
            if playbackRateChanged {
                self.playbackRate = state.playbackRate
            }
            
            if state.bundleIdentifier != self.bundleIdentifier {
                self.bundleIdentifier = state.bundleIdentifier
            }
            
            // Update shuffle and repeat state from controller
            if state.isShuffled != self.isShuffled {
                self.isShuffled = state.isShuffled
            }
            
            if state.repeatMode != self.repeatMode {
                self.repeatMode = state.repeatMode
            }
            
            // Update timestamp - use current time if state doesn't provide recent timestamp
            let stateTimestamp = state.lastUpdated
            let now = Date()
            
            // If the state timestamp is very recent (within 1 second), use it
            // Otherwise, use current time for better real-time calculation
            if abs(stateTimestamp.timeIntervalSince(now)) < 1.0 {
                self.timestampDate = stateTimestamp
            } else {
                self.timestampDate = now
            }
        }
        
        // Execute the batch update on the main thread
        DispatchQueue.main.async(execute: updateBatch)
    }
    
    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()
        
        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }
        
        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async {
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    if self.lastUpdated.timeIntervalSinceNow < -Defaults[.waitInterval] {
                        withAnimation {
                            self.isPlayerIdle = !self.isPlaying
                        }
                    }
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self?.calculateAverageColor()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }
    
    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }
    
    func play() {
        Task {
            await activeController?.play()
        }
    }
    
    func pause() {
        Task {
            await activeController?.pause()
        }
    }
    
    func toggleShuffle() {
        Task {
            // Provide immediate UI feedback
            await MainActor.run {
                self.isShuffled.toggle()
            }
            
            // Execute the actual command
            await activeController?.toggleShuffle()
            
            // Note: The actual state will be updated when the controller reports back
            // via updateFromPlaybackState if the command provides status feedback
        }
    }

    func toggleRepeat() {
        Task {
            // Provide immediate UI feedback
            await MainActor.run {
                switch self.repeatMode {
                case .off:
                    self.repeatMode = .all
                case .all:
                    self.repeatMode = .one
                case .one:
                    self.repeatMode = .off
                }
            }
            
            // Execute the actual command
            await activeController?.toggleRepeat()
            
            // Note: The actual state will be updated when the controller reports back
            // via updateFromPlaybackState if the command provides status feedback
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }
    
    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }
    
    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }
    
    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }
    
    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if  type(of: self?.activeController) == YouTubeMusicController.self,
                   let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
}
