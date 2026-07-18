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
import AVFoundation
import Combine
import CoreImage
import Defaults
import SkyLightWindow
import SwiftUI

// MARK: - Click Receiver Window

private class ClickReceiverWindow: NSWindow {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Keep left click inert so the fallback only dismisses on right click.
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class LoopingVideoView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func play(url: URL) {
        stop()

        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        layer.backgroundColor = NSColor.clear.cgColor

        self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.layer?.addSublayer(layer)

        playerLayer = layer
        queuePlayer = player
        playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        playerLooper = nil
        queuePlayer = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }

    func pause() {
        queuePlayer?.pause()
    }

    func resume() {
        queuePlayer?.play()
    }
}

private final class WallpaperTransitionImageView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(imageLayer)
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    func updateImage(_ image: NSImage) {
        imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

private final class SpotifyCanvasFallbackArtworkOverlayView: NSView {
    var onDismiss: (() -> Void)?

    private let imageLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var artwork: NSImage

    init(artwork: NSImage) {
        self.artwork = artwork
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.34).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 26
        layer?.shadowOffset = CGSize(width: 0, height: -22)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        imageLayer.contents = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.18).cgColor
        borderLayer.lineWidth = 1.1

        layer?.addSublayer(imageLayer)
        layer?.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()

        let radius = cornerRadius
        imageLayer.frame = bounds
        imageLayer.cornerRadius = radius
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.55, dy: 0.55),
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDismiss?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss?()
    }

    func updateArtwork(_ artwork: NSImage) {
        self.artwork = artwork
        imageLayer.contents = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil)
        needsLayout = true
    }

    private var aspectRatio: CGFloat {
        let height = max(artwork.size.height, 1)
        return artwork.size.width / height
    }

    private var cornerRadius: CGFloat {
        aspectRatio > 1 ? 16 : 34
    }
}

private struct FullScreenLyricsOverlayContent: View {
    let text: String
    let fontSize: CGFloat

    private var isPlaceholder: Bool {
        text == "Loading lyrics..." || text == "No lyrics found"
    }

    var body: some View {
        VStack {
            Text(text)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(isPlaceholder ? 0.72 : 0.94))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 6)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

private struct SpotifyCanvasFallbackLayoutFrames {
    let artworkFrame: NSRect
    let panelFrame: NSRect
    let groupFrame: NSRect
    let lyricsFrame: NSRect?
}

// MARK: - Window Manager

@MainActor
final class FullScreenArtworkWindowManager: ObservableObject {
    private enum ArtworkOverlayMode {
        case none
        case spotifyFallback
    }

    static let shared = FullScreenArtworkWindowManager()

    @Published private(set) var isShowing = false
    @Published private(set) var isShowingSpotifyCanvasFallback = false
    var onDismiss: (() -> Void)?

    private let wallpaperPlistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()
    private let backupPlistURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_wallpaper_backup.plist")
    }()
    private let aerialManifestURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json")
    }()
    private let aerialVideosDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
    }()
    private let aerialThumbnailsDirectoryURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
    }()
    private let customLiveWallpaperAssetID = "6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7"
    private let liveWallpaperManifestBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_manifest_backup.json")
    }()
    private let liveWallpaperVideoBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_video_backup.mov")
    }()
    private let liveWallpaperThumbnailBackupURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_aerial_thumbnail_backup.png")
    }()
    private var artworkFileURL: URL?
    private var cachedArtworkPNG: URL?
    private var cachedArtworkFingerprint: String?
    private var cachedBlurredArtworkPNG: URL?
    private var cachedBlurredArtworkFingerprint: String?
    private var cachedBlurredArtworkPixelSize: CGSize = .zero
    private var activeSongTitle: String?
    private var activeArtist: String?
    private var trackChangeCancellable: AnyCancellable?
    private var artworkCacheCancellable: AnyCancellable?
    private var videoArtworkCancellable: AnyCancellable?
    private var playbackStateCancellable: AnyCancellable?
    private var hasSuspendedWallpaperAgent = false
    private var appTerminationObserver: NSObjectProtocol?
    private var clickWindow: ClickReceiverWindow?
    private var clickWindowDelegated = false
    private var videoWindow: NSWindow?
    private var videoView: LoopingVideoView?
    private var activeVideoWindowURL: URL?
    private var videoWindowHideTask: Task<Void, Never>?
    private var artworkOverlayWindow: NSWindow?
    private var artworkOverlayWindowDelegated = false
    private var lyricsOverlayWindow: NSWindow?
    private var lyricsOverlayWindowDelegated = false
    private var currentArtworkOverlayMode: ArtworkOverlayMode = .none
    private var wallpaperTransitionWindow: NSWindow?
    private var wallpaperTransitionView: WallpaperTransitionImageView?
    private var wallpaperTransitionHideTask: Task<Void, Never>?
    private var panelFrameChangeObserver: NSObjectProtocol?
    private var liveWallpaperTask: Task<Void, Never>?
    private var deferredTrackRefreshTask: Task<Void, Never>?
    private var isLiveWallpaperAllowed = false
    private var activeLiveWallpaperFingerprint: String?
    private var activeWallpaperKey: String?
    private var pendingFallbackStaticURL: URL?
    private var pendingFallbackWallpaperKey: String?
    private var originalDesktopImageURLs: [String: URL] = [:]
    private var didCaptureStaticBackup = false
    private var appliedStaticWallpaper = false
    private var didApplyAerialWallpaper = false
    private var fallbackRightClickMonitor: Any?
    private var artworkLayoutOverCanvasPreferenceCancellable: AnyCancellable?
    private var lyricsTextCancellable: AnyCancellable?
    private var lyricsPreferenceCancellable: AnyCancellable?
    private let spotifyCanvasFallbackHorizontalMargin: CGFloat = 48

    private init() {
        observeArtworkChanges()
        observeVideoArtworkChanges()
        observePanelFrameChanges()
        observeArtworkLayoutOverCanvasPreference()
        observeLyricsChanges()
        observeLyricsPreference()
        observePlaybackStateChanges()
        observeAppTermination()
    }

    func show(artwork: NSImage, videoURL: URL? = nil, allowLiveWallpaper: Bool = false) {
        guard !isShowing else { return }
        guard let screen = NSScreen.main else { return }
        applyPresentation(
            artwork: artwork,
            videoURL: videoURL,
            allowLiveWallpaper: allowLiveWallpaper,
            on: screen,
            backupWallpaperConfiguration: true
        )
        observeTrackChanges()
    }

    func hide() {
        guard isShowing else { return }
        resumeWallpaperAgentIfNeeded()
        isShowing = false
        isLiveWallpaperAllowed = false
        activeLiveWallpaperFingerprint = nil
        activeWallpaperKey = nil
        pendingFallbackStaticURL = nil
        pendingFallbackWallpaperKey = nil
        let shouldRestoreStandardPanelLayout = isShowingSpotifyCanvasFallback
        isShowingSpotifyCanvasFallback = false
        removeFallbackRightClickMonitor()
        trackChangeCancellable?.cancel()
        trackChangeCancellable = nil
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil
        deferredTrackRefreshTask?.cancel()
        deferredTrackRefreshTask = nil

        hideVideoWindow()
        hideArtworkOverlay()
        hideLyricsOverlay()
        hideWallpaperTransition()
        hideClickReceiver()
        if shouldRestoreStandardPanelLayout, LockScreenManager.shared.isLocked {
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: true)
        }
        restoreWallpaper()

        activeSongTitle = nil
        activeArtist = nil

        let callback = onDismiss
        onDismiss = nil
        callback?()

        print("[FullScreenArtworkWindowManager] Original wallpaper restored")
    }

    // MARK: - Artwork Pre-Cache

    private func observeArtworkChanges() {
        artworkCacheCancellable = MusicManager.shared.$albumArt
            .debounce(for: .milliseconds(180), scheduler: DispatchQueue.main)
            .sink { [weak self] newArt in
                guard let self else { return }
                guard let fingerprint = self.imageFingerprint(for: newArt) else { return }
                guard fingerprint != self.cachedArtworkFingerprint else { return }
                let url = self.artworkCacheFileURL(for: fingerprint)
                Task.detached(priority: .utility) {
                    guard let pngData = self.encodeToPNG(newArt) else { return }
                    try? pngData.write(to: url, options: .atomic)
                    await MainActor.run {
                        self.cachedArtworkPNG = url
                        self.cachedArtworkFingerprint = fingerprint
                        if self.isShowing {
                            self.refreshPresentationForCurrentTrack()
                        }
                    }
                }
            }
    }

    private func observeVideoArtworkChanges() {
        videoArtworkCancellable = MusicManager.shared.$videoArtworkURL
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                self.refreshPresentationForCurrentTrack()
            }
    }

    private func observePlaybackStateChanges() {
        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.applyCanvasPlaybackState(isPlaying: isPlaying)
            }
    }

    private static let wallpaperRenderProcessNames: [String] = [
        "WallpaperAgent",
        "WallpaperAerialsExtension",
        "WallpaperVideoExtension",
        "wallpaperexportd"
    ]

    private func applyCanvasPlaybackState(isPlaying: Bool) {
        if let videoView, videoWindow != nil {
            if isPlaying {
                videoView.resume()
            } else {
                videoView.pause()
            }
        }

        let canSuspend = isShowing && isLiveWallpaperAllowed && activeLiveWallpaperFingerprint != nil
        print("[FullScreenArtworkWindowManager] playback state -> isPlaying=\(isPlaying) showing=\(isShowing) liveAllowed=\(isLiveWallpaperAllowed) fingerprint=\(activeLiveWallpaperFingerprint ?? "nil")")

        if isPlaying {
            resumeWallpaperAgentIfNeeded()
        } else if canSuspend {
            suspendWallpaperAgent()
        }
    }

    private func suspendWallpaperAgent() {
        guard !hasSuspendedWallpaperAgent else { return }
        var anySucceeded = false
        for name in Self.wallpaperRenderProcessNames {
            if signalProcess(name: name, signalFlag: "-STOP") {
                anySucceeded = true
            }
        }
        hasSuspendedWallpaperAgent = anySucceeded
        print("[FullScreenArtworkWindowManager] SIGSTOP wallpaper processes -> anySucceeded=\(anySucceeded)")
    }

    private func resumeWallpaperAgentIfNeeded() {
        guard hasSuspendedWallpaperAgent else { return }
        for name in Self.wallpaperRenderProcessNames {
            _ = signalProcess(name: name, signalFlag: "-CONT")
        }
        hasSuspendedWallpaperAgent = false
        print("[FullScreenArtworkWindowManager] SIGCONT wallpaper processes")
    }

    @discardableResult
    private func signalProcess(name: String, signalFlag: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = [signalFlag, name]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("[FullScreenArtworkWindowManager] killall \(signalFlag) \(name) threw: \(error)")
            return false
        }
    }

    private func observeAppTermination() {
        appTerminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeWallpaperAgentIfNeeded()
        }
    }

    private func applyPresentation(
        artwork: NSImage,
        videoURL: URL?,
        allowLiveWallpaper: Bool,
        on screen: NSScreen,
        backupWallpaperConfiguration: Bool
    ) {
        let artworkID = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
        guard let artworkFingerprint = imageFingerprint(for: artwork) else { return }
        isLiveWallpaperAllowed = allowLiveWallpaper
        let shouldUseStaticFallbackWallpaper = shouldUseBlurredStaticWallpaper(videoURL: videoURL)
        let shouldUseFallbackLayout = shouldUseSpotifyFallbackLayout(videoURL: videoURL)
        let effectiveVideoURL = resolvedVideoURL(videoURL: videoURL)
        let overlayMode = artworkOverlayMode(shouldUseFallbackLayout: shouldUseFallbackLayout)
        let previousFallbackState = isShowingSpotifyCanvasFallback

        guard let rawArtworkFileURL = persistedArtworkFileURL(for: artwork, fingerprint: artworkFingerprint) else { return }
        let expectCanvas = effectiveVideoURL != nil
        let blurredFallbackURL = blurredWallpaperFileURL(for: artwork, fingerprint: artworkFingerprint, screen: screen) ?? rawArtworkFileURL
        let wallpaperURL = (shouldUseStaticFallbackWallpaper || expectCanvas)
            ? blurredFallbackURL
            : rawArtworkFileURL
        let wallpaperKey = wallpaperIdentityKey(
            fingerprint: artworkFingerprint,
            usesFallback: shouldUseStaticFallbackWallpaper || expectCanvas,
            screen: screen
        )
        let desiredLiveWallpaperFingerprint = effectiveVideoURL?.absoluteString
        let requiresWallpaperRefresh = backupWallpaperConfiguration
            || activeWallpaperKey != wallpaperKey
            || activeLiveWallpaperFingerprint != desiredLiveWallpaperFingerprint

        artworkFileURL = wallpaperURL

        if backupWallpaperConfiguration {
            backupWallpaperConfig()
        }

        if requiresWallpaperRefresh {
            if expectCanvas {
                pendingFallbackStaticURL = blurredFallbackURL
                pendingFallbackWallpaperKey = wallpaperKey
                activeWallpaperKey = nil
                activeLiveWallpaperFingerprint = nil
            } else {
                showWallpaperTransition(on: screen, imageURL: wallpaperURL)

                if backupWallpaperConfiguration {
                    captureStaticWallpaperBackupIfNeeded()
                }

                guard applyStaticWallpaper(imageURL: wallpaperURL) else {
                    print("[FullScreenArtworkWindowManager] Failed to set desktop image")
                    hideWallpaperTransition()
                    return
                }

                activeWallpaperKey = wallpaperKey
                activeLiveWallpaperFingerprint = nil
                pendingFallbackStaticURL = nil
                pendingFallbackWallpaperKey = nil
            }
        }

        isShowing = true
        isShowingSpotifyCanvasFallback = shouldUseFallbackLayout
        activeSongTitle = MusicManager.shared.songTitle
        activeArtist = MusicManager.shared.artistName

        if overlayMode == .spotifyFallback {
            installFallbackRightClickMonitorIfNeeded()
        } else {
            removeFallbackRightClickMonitor()
        }

        if overlayMode == .none {
            hideArtworkOverlay()
        } else {
            showArtworkOverlay(on: screen, artwork: artwork, mode: overlayMode)
        }

        updateLyricsOverlayIfNeeded(on: screen)

        if previousFallbackState != shouldUseFallbackLayout, LockScreenManager.shared.isLocked {
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: true)
        }

        showClickReceiver(on: screen)
        scheduleLiveWallpaperPreparation(for: effectiveVideoURL, artwork: artwork, identifier: artworkID)

        if effectiveVideoURL == nil {
            hideVideoWindow()
            scheduleWallpaperTransitionHide(after: .milliseconds(900))
        }

        print("[FullScreenArtworkWindowManager] Artwork applied as wallpaper")
    }

    private func refreshPresentationForCurrentTrack() {
        guard isShowing else { return }
        guard MusicManager.shared.hasActiveSession else { return }
        guard let screen = NSScreen.main else { return }

        applyPresentation(
            artwork: MusicManager.shared.albumArt,
            videoURL: isLiveWallpaperAllowed ? MusicManager.shared.videoArtworkURL : nil,
            allowLiveWallpaper: isLiveWallpaperAllowed,
            on: screen,
            backupWallpaperConfiguration: false
        )
    }

    private func observePanelFrameChanges() {
        panelFrameChangeObserver = NotificationCenter.default.addObserver(
            forName: .atollLockScreenPanelFrameDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateArtworkOverlayFrameIfNeeded()
                self?.updateLyricsOverlayIfNeeded()
            }
        }
    }

    private func observeArtworkLayoutOverCanvasPreference() {
        artworkLayoutOverCanvasPreferenceCancellable = Defaults.publisher(.lockScreenUseArtworkLayoutOverFullscreenCanvas)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.refreshPresentationForCurrentTrack()
            }
    }

    private func observeLyricsChanges() {
        lyricsTextCancellable = MusicManager.shared.$currentLyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.updateLyricsOverlayIfNeeded()
            }
    }

    private func observeLyricsPreference() {
        lyricsPreferenceCancellable = Defaults.publisher(.enableLyrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isShowing else { return }
                self.updateLyricsOverlayIfNeeded()
            }
    }

    private func shouldUseBlurredStaticWallpaper(videoURL: URL?) -> Bool {
        let bundle = MusicManager.shared.bundleIdentifier
        if bundle == AmazonMusicController.bundleIdentifier {
            return true
        }
        if bundle == SpotifyController.bundleIdentifier {
            return videoURL == nil
        }
        return false
    }

    private func shouldUseSpotifyFallbackLayout(videoURL: URL?) -> Bool {
        let bundle = MusicManager.shared.bundleIdentifier
        if bundle == AmazonMusicController.bundleIdentifier {
            return true
        }
        guard bundle == SpotifyController.bundleIdentifier else {
            return false
        }

        if videoURL == nil {
            return true
        }

        return Defaults[.lockScreenUseArtworkLayoutOverFullscreenCanvas]
    }

    private func resolvedVideoURL(videoURL: URL?) -> URL? {
        guard isLiveWallpaperAllowed else { return nil }
        return videoURL
    }

    private func artworkOverlayMode(shouldUseFallbackLayout: Bool) -> ArtworkOverlayMode {
        if shouldUseFallbackLayout {
            return .spotifyFallback
        }

        return .none
    }

    func spotifyCanvasFallbackInterItemSpacing(screenFrame: NSRect) -> CGFloat {
        min(max(screenFrame.width * 0.018, 28), 42)
    }

    func spotifyCanvasFallbackArtworkSideLength(screenFrame: NSRect, panelSize: CGSize) -> CGFloat {
        let preferred = min(max(screenFrame.height * 0.28, 250), 330)
        let spacing = spotifyCanvasFallbackInterItemSpacing(screenFrame: screenFrame)
        let maxByWidth = max(
            min(screenFrame.width - (spotifyCanvasFallbackHorizontalMargin * 2) - spacing - panelSize.width, 360),
            180
        )
        let maxByHeight = max(min(screenFrame.height * 0.42, 360), 180)
        return min(preferred, maxByWidth, maxByHeight)
    }

    private func persistedArtworkFileURL(for artwork: NSImage, fingerprint: String) -> URL? {
        if let cached = cachedArtworkPNG,
           cachedArtworkFingerprint == fingerprint,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard let encoded = encodeToPNG(artwork) else { return nil }

        let tempURL = artworkCacheFileURL(for: fingerprint)

        do {
            try encoded.write(to: tempURL, options: .atomic)
            cachedArtworkPNG = tempURL
            cachedArtworkFingerprint = fingerprint
            return tempURL
        } catch {
            return nil
        }
    }

    private func blurredWallpaperFileURL(for artwork: NSImage, fingerprint: String, screen: NSScreen) -> URL? {
        let pixelSize = wallpaperPixelSize(for: screen)

        if let cached = cachedBlurredArtworkPNG,
           cachedBlurredArtworkFingerprint == fingerprint,
           cachedBlurredArtworkPixelSize == pixelSize,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        guard let encoded = encodeBlurredWallpaperPNG(from: artwork, targetPixelSize: pixelSize) else {
            return nil
        }

        let tempURL = blurredArtworkCacheFileURL(for: fingerprint, pixelSize: pixelSize)

        do {
            try encoded.write(to: tempURL, options: .atomic)
            cachedBlurredArtworkPNG = tempURL
            cachedBlurredArtworkFingerprint = fingerprint
            cachedBlurredArtworkPixelSize = pixelSize
            return tempURL
        } catch {
            return nil
        }
    }

    private func wallpaperPixelSize(for screen: NSScreen) -> CGSize {
        let scale = max(screen.backingScaleFactor, 1)
        let frame = screen.frame
        return CGSize(
            width: max(frame.width * scale, 1),
            height: max(frame.height * scale, 1)
        )
    }

    private func artworkCacheFileURL(for fingerprint: String) -> URL {
        let normalizedFingerprint = normalizedFingerprintComponent(fingerprint)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_artwork_wallpaper_\(normalizedFingerprint).png")
    }

    private func blurredArtworkCacheFileURL(for fingerprint: String, pixelSize: CGSize) -> URL {
        let normalizedFingerprint = normalizedFingerprintComponent(fingerprint)
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll_artwork_wallpaper_blurred_\(normalizedFingerprint)_\(width)x\(height).png")
    }

    private func normalizedFingerprintComponent(_ fingerprint: String) -> String {
        fingerprint.replacingOccurrences(of: "-", with: "_")
    }

    private func wallpaperIdentityKey(fingerprint: String, usesFallback: Bool, screen: NSScreen) -> String {
        if usesFallback {
            let pixelSize = wallpaperPixelSize(for: screen)
            let width = Int(pixelSize.width.rounded())
            let height = Int(pixelSize.height.rounded())
            return "fallback:\(fingerprint):\(width)x\(height)"
        }

        return "artwork:\(fingerprint)"
    }

    private nonisolated func encodeToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private nonisolated func imageFingerprint(for image: NSImage) -> String? {
        guard let pngData = encodeToPNG(image) else { return nil }
        var hasher = Hasher()
        hasher.combine(pngData)
        hasher.combine(Int(image.size.width.rounded()))
        hasher.combine(Int(image.size.height.rounded()))
        return String(hasher.finalize())
    }

    private func encodeBlurredWallpaperPNG(from artwork: NSImage, targetPixelSize: CGSize) -> Data? {
        guard let tiffData = artwork.tiffRepresentation,
              let sourceImage = CIImage(data: tiffData)
        else { return nil }

        let targetRect = CGRect(origin: .zero, size: targetPixelSize)
        let sourceExtent = sourceImage.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else { return nil }

        let scale = max(
            targetRect.width / sourceExtent.width,
            targetRect.height / sourceExtent.height
        )
        let scaledWidth = sourceExtent.width * scale
        let scaledHeight = sourceExtent.height * scale
        let offsetX = (targetRect.width - scaledWidth) / 2
        let offsetY = (targetRect.height - scaledHeight) / 2

        let scaledImage = sourceImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))
            .cropped(to: targetRect)

        let blurredImage = scaledImage
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28])
            .cropped(to: targetRect)
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0.92,
                    kCIInputBrightnessKey: -0.03,
                    kCIInputContrastKey: 0.98
                ]
            )

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(blurredImage, from: targetRect) else { return nil }

        let renderedImage = NSImage(cgImage: cgImage, size: NSSize(width: targetPixelSize.width, height: targetPixelSize.height))
        let composedImage = NSImage(size: renderedImage.size)

        composedImage.lockFocus()
        renderedImage.draw(in: NSRect(origin: .zero, size: renderedImage.size))

        NSColor(calibratedWhite: 0.02, alpha: 0.08).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: renderedImage.size)).fill()

        let gradient = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.05),
            NSColor.clear,
            NSColor.black.withAlphaComponent(0.16)
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: renderedImage.size), angle: -90)
        composedImage.unlockFocus()

        guard let finalTIFF = composedImage.tiffRepresentation,
              let finalBitmap = NSBitmapImageRep(data: finalTIFF)
        else { return nil }

        return finalBitmap.representation(using: .png, properties: [:])
    }

    private func applyDeferredStaticFallback() {
        guard let url = pendingFallbackStaticURL else { return }
        let key = pendingFallbackWallpaperKey
        pendingFallbackStaticURL = nil
        pendingFallbackWallpaperKey = nil

        if let screen = NSScreen.main {
            showWallpaperTransition(on: screen, imageURL: url)
        }
        captureStaticWallpaperBackupIfNeeded()
        guard applyStaticWallpaper(imageURL: url) else {
            print("[FullScreenArtworkWindowManager] Failed to apply deferred static fallback")
            hideWallpaperTransition()
            return
        }
        activeWallpaperKey = key
        activeLiveWallpaperFingerprint = nil
        hideVideoWindow()
        scheduleWallpaperTransitionHide(after: .milliseconds(900))
    }

    private func scheduleLiveWallpaperPreparation(for videoURL: URL?, artwork: NSImage, identifier: String) {
        liveWallpaperTask?.cancel()
        liveWallpaperTask = nil

        guard isLiveWallpaperAllowed else {
            scheduleWallpaperTransitionHide(after: .milliseconds(260))
            return
        }

        guard let videoURL else {
            scheduleWallpaperTransitionHide(after: .milliseconds(260))
            return
        }

        let nextFingerprint = videoURL.absoluteString
        if activeLiveWallpaperFingerprint == nextFingerprint {
            scheduleWallpaperTransitionHide(after: .milliseconds(220))
            scheduleHideVideoWindow(after: .milliseconds(220), expectedURL: videoURL)
            return
        }

        if let screen = NSScreen.main {
            showVideoWindow(on: screen, videoURL: videoURL)
        }
        scheduleWallpaperTransitionHide(after: .milliseconds(420))

        let assetID = customLiveWallpaperAssetID
        let manifestURL = aerialManifestURL
        let videosDirectoryURL = aerialVideosDirectoryURL
        let thumbnailsDirectoryURL = aerialThumbnailsDirectoryURL
        let manifestBackupURL = liveWallpaperManifestBackupURL
        let videoBackupURL = liveWallpaperVideoBackupURL
        let thumbnailBackupURL = liveWallpaperThumbnailBackupURL
        let thumbnailData = encodeToPNG(artwork)
        let title = activeSongTitle ?? MusicManager.shared.songTitle
        let artist = activeArtist ?? MusicManager.shared.artistName
        let displayName = [title, artist]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")

        liveWallpaperTask = Task(priority: .utility) { [weak self] in
            let prepared = await Self.prepareCustomLiveWallpaperAsset(
                from: videoURL,
                assetID: assetID,
                displayName: displayName.isEmpty ? "Atoll Canvas" : displayName,
                manifestURL: manifestURL,
                videosDirectoryURL: videosDirectoryURL,
                thumbnailsDirectoryURL: thumbnailsDirectoryURL,
                thumbnailData: thumbnailData,
                manifestBackupURL: manifestBackupURL,
                videoBackupURL: videoBackupURL,
                thumbnailBackupURL: thumbnailBackupURL
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.isShowing, self.isLiveWallpaperAllowed else { return }
                let currentIdentifier = "\(MusicManager.shared.songTitle)|\(MusicManager.shared.artistName)"
                let currentVideoURL = self.isLiveWallpaperAllowed ? MusicManager.shared.videoArtworkURL : nil
                guard currentIdentifier == identifier else { return }
                guard currentVideoURL?.absoluteString == nextFingerprint else { return }
                guard !self.shouldUseBlurredStaticWallpaper(videoURL: currentVideoURL) else { return }
                guard prepared else {
                    self.applyDeferredStaticFallback()
                    return
                }
                guard self.applyAerialToPlist(assetID: assetID) else {
                    self.applyDeferredStaticFallback()
                    return
                }

                self.activeLiveWallpaperFingerprint = nextFingerprint
                self.didApplyAerialWallpaper = true
                self.pendingFallbackStaticURL = nil
                self.pendingFallbackWallpaperKey = nil
                self.restartWallpaperAgent()
                self.scheduleHideVideoWindow(after: .milliseconds(950), expectedURL: videoURL)
                print("[FullScreenArtworkWindowManager] Live wallpaper applied")
            }
        }
    }

    private nonisolated static func prepareCustomLiveWallpaperAsset(
        from sourceURL: URL,
        assetID: String,
        displayName: String,
        manifestURL: URL,
        videosDirectoryURL: URL,
        thumbnailsDirectoryURL: URL,
        thumbnailData: Data?,
        manifestBackupURL: URL,
        videoBackupURL: URL,
        thumbnailBackupURL: URL
    ) async -> Bool {
        let fm = FileManager.default
        let videoDestinationURL = videosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = thumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        do {
            try fm.createDirectory(at: videosDirectoryURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: thumbnailsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return false
        }

        backupItemIfNeeded(at: manifestURL, backupURL: manifestBackupURL)
        backupItemIfNeeded(at: videoDestinationURL, backupURL: videoBackupURL)
        backupItemIfNeeded(at: thumbnailDestinationURL, backupURL: thumbnailBackupURL)

        guard await materializeVideo(from: sourceURL, to: videoDestinationURL) else {
            return false
        }

        if let thumbnailData {
            try? thumbnailData.write(to: thumbnailDestinationURL, options: .atomic)
        }

        return updateAerialManifest(
            manifestURL: manifestURL,
            assetID: assetID,
            videoURL: videoDestinationURL,
            thumbnailURL: fm.fileExists(atPath: thumbnailDestinationURL.path) ? thumbnailDestinationURL : nil,
            displayName: displayName
        )
    }

    private nonisolated static func materializeVideo(from sourceURL: URL, to destinationURL: URL) async -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)

        if !sourceURL.isFileURL {
            guard let downloadedURL = await downloadRemoteVideo(from: sourceURL) else {
                return false
            }
            defer { try? fm.removeItem(at: downloadedURL) }
            return await materializeVideo(from: downloadedURL, to: destinationURL)
        }

        if sourceURL.isFileURL, sourceURL.pathExtension.lowercased() == "mov" {
            do {
                try fm.copyItem(at: sourceURL, to: destinationURL)
                return validateVideo(at: destinationURL)
            } catch {
                return false
            }
        }

        let asset = AVURLAsset(url: sourceURL)
        let presets = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        for preset in presets {
            try? fm.removeItem(at: destinationURL)
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }

            exportSession.outputURL = destinationURL
            exportSession.outputFileType = .mov
            exportSession.shouldOptimizeForNetworkUse = true

            let exported = await export(exportSession)
            if exported, validateVideo(at: destinationURL) {
                return true
            }
        }

        return false
    }

    private nonisolated static func downloadRemoteVideo(from sourceURL: URL) async -> URL? {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private nonisolated static func export(_ exportSession: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume(returning: exportSession.status == .completed)
            }
        }
    }

    private nonisolated static func validateVideo(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        return !asset.tracks(withMediaType: .video).isEmpty
    }

    private nonisolated static func updateAerialManifest(
        manifestURL: URL,
        assetID: String,
        videoURL: URL,
        thumbnailURL: URL?,
        displayName: String
    ) -> Bool {
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var root = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]]
        else {
            return false
        }

        guard let existingIndex = assets.firstIndex(where: { ($0["id"] as? String) == assetID }) else {
            return false
        }

        var customAsset = assets[existingIndex]
        customAsset["accessibilityLabel"] = displayName
        customAsset["previewImage"] = thumbnailURL?.absoluteString ?? ""
        customAsset["url-4K-SDR-240FPS"] = videoURL.absoluteString
        customAsset["pointsOfInterest"] = [:]
        assets[existingIndex] = customAsset

        root["assets"] = assets

        guard let encoded = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return false
        }

        do {
            try encoded.write(to: manifestURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func backupItemIfNeeded(at sourceURL: URL, backupURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else { return }
        guard !fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.copyItem(at: sourceURL, to: backupURL)
    }

    private func restoreLiveWallpaperResources() {
        let fm = FileManager.default
        let assetID = customLiveWallpaperAssetID
        let videoDestinationURL = aerialVideosDirectoryURL.appendingPathComponent("\(assetID).mov")
        let thumbnailDestinationURL = aerialThumbnailsDirectoryURL.appendingPathComponent("\(assetID).png")

        if fm.fileExists(atPath: liveWallpaperManifestBackupURL.path) {
            try? fm.removeItem(at: aerialManifestURL)
            try? fm.copyItem(at: liveWallpaperManifestBackupURL, to: aerialManifestURL)
            try? fm.removeItem(at: liveWallpaperManifestBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperVideoBackupURL.path) {
            try? fm.removeItem(at: videoDestinationURL)
            try? fm.copyItem(at: liveWallpaperVideoBackupURL, to: videoDestinationURL)
            try? fm.removeItem(at: liveWallpaperVideoBackupURL)
        }

        if fm.fileExists(atPath: liveWallpaperThumbnailBackupURL.path) {
            try? fm.removeItem(at: thumbnailDestinationURL)
            try? fm.copyItem(at: liveWallpaperThumbnailBackupURL, to: thumbnailDestinationURL)
            try? fm.removeItem(at: liveWallpaperThumbnailBackupURL)
        }
    }

    // MARK: - Click Receiver

    private func installFallbackRightClickMonitorIfNeeded() {
        guard fallbackRightClickMonitor == nil else { return }

        fallbackRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, self.isShowing, self.isShowingSpotifyCanvasFallback else {
                return event
            }

            self.hide()
            return nil
        }
    }

    private func removeFallbackRightClickMonitor() {
        guard let fallbackRightClickMonitor else { return }
        NSEvent.removeMonitor(fallbackRightClickMonitor)
        self.fallbackRightClickMonitor = nil
    }

    private func showClickReceiver(on screen: NSScreen) {
        let screenFrame = screen.frame

        let window: ClickReceiverWindow
        if let existing = clickWindow {
            window = existing
        } else {
            let newWindow = ClickReceiverWindow(
                contentRect: screenFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            clickWindow = newWindow
            window = newWindow
            clickWindowDelegated = false
        }

        window.setFrame(screenFrame, display: true)
        window.onClick = { [weak self] in
            self?.hide()
        }

        if !clickWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            clickWindowDelegated = true
        }

        window.orderFrontRegardless()

        for other in NSApp.windows where other !== window && other.level.rawValue >= Int(CGShieldingWindowLevel()) && other.isVisible {
            window.order(.below, relativeTo: other.windowNumber)
        }
    }

    private func hideClickReceiver() {
        clickWindow?.orderOut(nil)
        clickWindow?.onClick = nil
    }

    private func showArtworkOverlay(on screen: NSScreen, artwork: NSImage, mode: ArtworkOverlayMode) {
        currentArtworkOverlayMode = mode
        guard let targetFrame = artworkOverlayFrame(on: screen) else { return }

        let window: NSWindow
        if let existing = artworkOverlayWindow {
            window = existing
        } else {
            let newWindow = NSWindow(
                contentRect: targetFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = false
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            artworkOverlayWindow = newWindow
            window = newWindow
            artworkOverlayWindowDelegated = false
        }

        window.setFrame(targetFrame, display: true)

        let contentView: SpotifyCanvasFallbackArtworkOverlayView
        if let existing = window.contentView as? SpotifyCanvasFallbackArtworkOverlayView {
            contentView = existing
            contentView.frame = NSRect(origin: .zero, size: targetFrame.size)
            contentView.updateArtwork(artwork)
        } else {
            let newContentView = SpotifyCanvasFallbackArtworkOverlayView(artwork: artwork)
            newContentView.frame = NSRect(origin: .zero, size: targetFrame.size)
            window.contentView = newContentView
            contentView = newContentView
        }

        contentView.onDismiss = { [weak self] in
            self?.hide()
        }

        if !artworkOverlayWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            artworkOverlayWindowDelegated = true
        }

        window.orderFrontRegardless()
    }

    private func hideArtworkOverlay() {
        currentArtworkOverlayMode = .none
        if let contentView = artworkOverlayWindow?.contentView as? SpotifyCanvasFallbackArtworkOverlayView {
            contentView.onDismiss = nil
        }
        artworkOverlayWindow?.orderOut(nil)
        artworkOverlayWindow?.contentView = nil
    }

    private func updateArtworkOverlayFrameIfNeeded() {
        guard isShowing, currentArtworkOverlayMode != .none else { return }
        guard let window = artworkOverlayWindow else { return }
        guard let screen = NSScreen.main, let frame = artworkOverlayFrame(on: screen) else { return }
        window.setFrame(frame, display: true)
    }

    private func artworkOverlayFrame(on screen: NSScreen) -> NSRect? {
        switch currentArtworkOverlayMode {
        case .none:
            return nil
        case .spotifyFallback:
            return spotifyFallbackArtworkOverlayFrame(on: screen)
        }
    }

    private func spotifyFallbackArtworkOverlayFrame(on screen: NSScreen) -> NSRect? {
        guard let frames = spotifyCanvasFallbackLayoutFrames(on: screen) else { return nil }
        return frames.artworkFrame
    }

    private func updateLyricsOverlayIfNeeded(on screen: NSScreen? = NSScreen.main) {
        guard isShowing, isShowingSpotifyCanvasFallback, Defaults[.enableLyrics] else {
            hideLyricsOverlay()
            return
        }

        let line = MusicManager.shared.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            hideLyricsOverlay()
            return
        }

        guard let screen, let frame = spotifyCanvasFallbackLayoutFrames(on: screen)?.lyricsFrame else {
            hideLyricsOverlay()
            return
        }

        let fontSize = min(max(frame.height * 0.24, 24), 40)
        let content = FullScreenLyricsOverlayContent(text: line, fontSize: fontSize)

        let window: NSWindow
        let hostingView: NSHostingView<FullScreenLyricsOverlayContent>
        if let existingWindow = lyricsOverlayWindow,
           let existingView = existingWindow.contentView as? NSHostingView<FullScreenLyricsOverlayContent> {
            window = existingWindow
            hostingView = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newHostingView = NSHostingView(rootView: content)
            newHostingView.frame = NSRect(origin: .zero, size: frame.size)
            newHostingView.wantsLayer = true
            newHostingView.layer?.backgroundColor = NSColor.clear.cgColor
            newWindow.contentView = newHostingView

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)
            lyricsOverlayWindow = newWindow
            window = newWindow
            hostingView = newHostingView
            lyricsOverlayWindowDelegated = false
        }

        window.setFrame(frame, display: true)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.rootView = content

        if !lyricsOverlayWindowDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            lyricsOverlayWindowDelegated = true
        }

        window.orderFrontRegardless()
    }

    private func hideLyricsOverlay() {
        lyricsOverlayWindow?.orderOut(nil)
    }

    private func spotifyCanvasFallbackLayoutFrames(on screen: NSScreen) -> SpotifyCanvasFallbackLayoutFrames? {
        let screenFrame = screen.frame
        guard let panelFrame = LockScreenPanelManager.shared.latestFrame else { return nil }

        let overlaySide = spotifyCanvasFallbackArtworkSideLength(
            screenFrame: screenFrame,
            panelSize: panelFrame.size
        )
        let spacing = spotifyCanvasFallbackInterItemSpacing(screenFrame: screenFrame)
        let targetX = panelFrame.minX - spacing - overlaySide
        let targetY = panelFrame.midY - (overlaySide / 2)
        let artworkFrame = NSRect(x: targetX, y: targetY, width: overlaySide, height: overlaySide)
        let groupFrame = artworkFrame.union(panelFrame)
        let lyricsGap = min(max(screenFrame.height * 0.022, 18), 28)
        let bottomMargin = min(max(screenFrame.height * 0.16, 140), 220)
        let availableHeight = groupFrame.minY - lyricsGap - (screenFrame.minY + bottomMargin)
        let desiredHeight = min(max(screenFrame.height * 0.13, 108), 156)
        let lyricsHeight = min(desiredHeight, max(availableHeight, 0))
        let lyricsFrame: NSRect?

        if lyricsHeight >= 56 {
            lyricsFrame = NSRect(
                x: groupFrame.minX,
                y: groupFrame.minY - lyricsGap - lyricsHeight,
                width: groupFrame.width,
                height: lyricsHeight
            )
        } else {
            lyricsFrame = nil
        }

        return SpotifyCanvasFallbackLayoutFrames(
            artworkFrame: artworkFrame,
            panelFrame: panelFrame,
            groupFrame: groupFrame,
            lyricsFrame: lyricsFrame
        )
    }

    private func showWallpaperTransition(on screen: NSScreen, imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }

        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = nil

        let screenFrame = screen.frame

        let window: NSWindow
        let view: WallpaperTransitionImageView

        if let existingWindow = wallpaperTransitionWindow, let existingView = wallpaperTransitionView {
            window = existingWindow
            view = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newView = WallpaperTransitionImageView(frame: screenFrame)
            newWindow.contentView = newView

            wallpaperTransitionWindow = newWindow
            wallpaperTransitionView = newView
            window = newWindow
            view = newView
        }

        window.setFrame(screenFrame, display: true)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        view.updateImage(image)
        window.orderFrontRegardless()
    }

    private func scheduleWallpaperTransitionHide(after delay: Duration) {
        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.hideWallpaperTransition()
        }
    }

    private func hideWallpaperTransition() {
        wallpaperTransitionHideTask?.cancel()
        wallpaperTransitionHideTask = nil
        wallpaperTransitionWindow?.orderOut(nil)
    }

    private func showVideoWindow(on screen: NSScreen, videoURL: URL) {
        videoWindowHideTask?.cancel()
        videoWindowHideTask = nil

        let screenFrame = screen.frame

        let window: NSWindow
        let view: LoopingVideoView

        if let existingWindow = videoWindow, let existingView = videoView {
            window = existingWindow
            view = existingView
        } else {
            let newWindow = NSWindow(
                contentRect: screenFrame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.ignoresMouseEvents = true
            newWindow.hasShadow = false
            newWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let newView = LoopingVideoView(frame: screenFrame)
            newWindow.contentView = newView

            videoWindow = newWindow
            videoView = newView
            window = newWindow
            view = newView
        }

        window.setFrame(screenFrame, display: true)
        view.frame = NSRect(origin: .zero, size: screenFrame.size)
        if activeVideoWindowURL != videoURL {
            view.play(url: videoURL)
            activeVideoWindowURL = videoURL
        }
        window.orderFrontRegardless()
        applyCanvasPlaybackState(isPlaying: MusicManager.shared.isPlaying)
    }

    private func scheduleHideVideoWindow(after delay: Duration, expectedURL: URL?) {
        videoWindowHideTask?.cancel()
        let expectedURLString = expectedURL?.absoluteString

        videoWindowHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }

            if let expectedURLString,
               self.activeVideoWindowURL?.absoluteString != expectedURLString {
                return
            }

            self.hideVideoWindow()
        }
    }

    private func hideVideoWindow() {
        videoWindowHideTask?.cancel()
        videoWindowHideTask = nil
        activeVideoWindowURL = nil
        videoView?.stop()
        videoWindow?.orderOut(nil)
    }

    // MARK: - Backup / Restore

    private var hasValidBackup: Bool {
        FileManager.default.fileExists(atPath: backupPlistURL.path)
    }

    private func backupWallpaperConfig() {
        guard !hasValidBackup else { return }
        try? FileManager.default.copyItem(at: wallpaperPlistURL, to: backupPlistURL)
    }

    private func screenKey(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen-\(number.uint32Value)"
        }
        return "screen-\(screen.localizedName)"
    }

    private func captureStaticWallpaperBackupIfNeeded() {
        guard !didCaptureStaticBackup else { return }
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            if let url = ws.desktopImageURL(for: screen) {
                originalDesktopImageURLs[screenKey(screen)] = url
            }
        }
        didCaptureStaticBackup = true
    }

    @discardableResult
    private func applyStaticWallpaper(imageURL: URL) -> Bool {
        let ws = NSWorkspace.shared
        var anySucceeded = false
        for screen in NSScreen.screens {
            let options = ws.desktopImageOptions(for: screen) ?? [:]
            do {
                try ws.setDesktopImageURL(imageURL, for: screen, options: options)
                anySucceeded = true
            } catch {
                print("[FullScreenArtworkWindowManager] setDesktopImageURL failed: \(error)")
            }
        }
        if anySucceeded {
            appliedStaticWallpaper = true
        }
        return anySucceeded
    }

    private func restoreStaticWallpaper() {
        guard appliedStaticWallpaper else { return }
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            guard let url = originalDesktopImageURLs[screenKey(screen)] else { continue }
            let options = ws.desktopImageOptions(for: screen) ?? [:]
            try? ws.setDesktopImageURL(url, for: screen, options: options)
        }
        appliedStaticWallpaper = false
        didCaptureStaticBackup = false
        originalDesktopImageURLs.removeAll()
    }

    private func applyArtworkToPlist(imageURL: URL) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopBlock = makeImageWallpaperBlock(imageURL: imageURL)
        let idleBlock = makeImageWallpaperBlock(imageURL: imageURL)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func applyAerialToPlist(assetID: String) -> Bool {
        guard let plistData = try? Data(contentsOf: wallpaperPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return false }

        let desktopTemplate = wallpaperBlock(
            named: "Desktop",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )
        let idleTemplate = wallpaperBlock(
            named: "Idle",
            in: plist["AllSpacesAndDisplays"] as? [String: Any],
            fallback: plist["SystemDefault"] as? [String: Any]
        )

        let desktopBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: desktopTemplate)
        let idleBlock = makeAerialWallpaperBlock(assetID: assetID, existingBlock: idleTemplate)

        patchWallpaperEntries(&plist, desktopBlock: desktopBlock, idleBlock: idleBlock)

        guard let newData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        else { return false }

        return (try? newData.write(to: wallpaperPlistURL, options: .atomic)) != nil
    }

    private func wallpaperBlock(named name: String, in primary: [String: Any]?, fallback: [String: Any]?) -> [String: Any]? {
        if let primaryBlock = primary?[name] as? [String: Any] {
            return primaryBlock
        }
        return fallback?[name] as? [String: Any]
    }

    private func makeImageWallpaperBlock(imageURL: URL) -> [String: Any] {
        let config: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString]
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let imageChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        let contentBlock: [String: Any] = [
            "Choices": [imageChoice],
            "Shuffle": "$null"
        ]

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func makeAerialWallpaperBlock(assetID: String, existingBlock: [String: Any]?) -> [String: Any] {
        let config: [String: Any] = [
            "assetID": assetID
        ]
        let configData = (try? PropertyListSerialization.data(fromPropertyList: config, format: .binary, options: 0)) ?? Data()

        let aerialChoice: [String: Any] = [
            "Provider": "com.apple.wallpaper.choice.aerials",
            "Files": [] as [Any],
            "Configuration": configData
        ]

        var contentBlock: [String: Any] = [
            "Choices": [aerialChoice],
            "Shuffle": "$null"
        ]

        if let existingContent = existingBlock?["Content"] as? [String: Any],
           let encodedOptionValues = existingContent["EncodedOptionValues"] {
            contentBlock["EncodedOptionValues"] = encodedOptionValues
        }

        return [
            "Content": contentBlock,
            "LastSet": Date(),
            "LastUse": Date()
        ]
    }

    private func patchWallpaperEntries(_ plist: inout [String: Any], desktopBlock: [String: Any], idleBlock: [String: Any]) {
        var allSpaces = (plist["AllSpacesAndDisplays"] as? [String: Any]) ?? [:]
        allSpaces["Desktop"] = desktopBlock
        allSpaces["Idle"] = idleBlock
        allSpaces["Type"] = "individual"
        plist["AllSpacesAndDisplays"] = allSpaces

        var systemDefault = (plist["SystemDefault"] as? [String: Any]) ?? [:]
        systemDefault["Desktop"] = desktopBlock
        systemDefault["Idle"] = idleBlock
        systemDefault["Type"] = "individual"
        plist["SystemDefault"] = systemDefault

        if var displays = plist["Displays"] as? [String: Any] {
            for key in displays.keys {
                if var display = displays[key] as? [String: Any] {
                    display["Desktop"] = desktopBlock
                    display["Idle"] = idleBlock
                    if display["Type"] != nil {
                        display["Type"] = "individual"
                    }
                    displays[key] = display
                }
            }
            plist["Displays"] = displays
        }

        if var spaces = plist["Spaces"] as? [String: Any] {
            for spaceKey in spaces.keys {
                if var space = spaces[spaceKey] as? [String: Any] {
                    if var defaultEntry = space["Default"] as? [String: Any] {
                        defaultEntry["Desktop"] = desktopBlock
                        defaultEntry["Idle"] = idleBlock
                        if defaultEntry["Type"] != nil {
                            defaultEntry["Type"] = "individual"
                        }
                        space["Default"] = defaultEntry
                    }
                    if var spaceDisplays = space["Displays"] as? [String: Any] {
                        for displayKey in spaceDisplays.keys {
                            if var display = spaceDisplays[displayKey] as? [String: Any] {
                                display["Desktop"] = desktopBlock
                                display["Idle"] = idleBlock
                                if display["Type"] != nil {
                                    display["Type"] = "individual"
                                }
                                spaceDisplays[displayKey] = display
                            }
                        }
                        space["Displays"] = spaceDisplays
                    }
                    spaces[spaceKey] = space
                }
            }
            plist["Spaces"] = spaces
        }
    }

    private func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
    }

    private func restoreWallpaper() {
        let fm = FileManager.default

        if appliedStaticWallpaper {
            restoreStaticWallpaper()
        }

        if didApplyAerialWallpaper, hasValidBackup {
            do {
                try fm.removeItem(at: wallpaperPlistURL)
                try fm.copyItem(at: backupPlistURL, to: wallpaperPlistURL)
                try fm.removeItem(at: backupPlistURL)
            } catch {
                print("[FullScreenArtworkWindowManager] Failed to restore plist: \(error)")
            }
            restoreLiveWallpaperResources()
            restartWallpaperAgent()
        } else if hasValidBackup {
            try? fm.removeItem(at: backupPlistURL)
        }

        didApplyAerialWallpaper = false
    }

    // MARK: - Track Change Observer

    private func observeTrackChanges() {
        trackChangeCancellable?.cancel()
        trackChangeCancellable = MusicManager.shared.$songTitle
            .combineLatest(MusicManager.shared.$artistName)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title, artist in
                guard let self, self.isShowing else { return }
                if title != self.activeSongTitle || artist != self.activeArtist {
                    self.refreshPresentationForCurrentTrack()
                    self.scheduleDeferredTrackRefresh(expectedTitle: title, expectedArtist: artist)
                }
            }
    }

    private func scheduleDeferredTrackRefresh(expectedTitle: String, expectedArtist: String) {
        deferredTrackRefreshTask?.cancel()
        deferredTrackRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.isShowing else { return }
            guard MusicManager.shared.songTitle == expectedTitle,
                  MusicManager.shared.artistName == expectedArtist
            else { return }

            self.refreshPresentationForCurrentTrack()
        }
    }
}
