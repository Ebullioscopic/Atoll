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

import SwiftUI
import Defaults

struct LockScreenMusicPanel: View {
    private struct GlassLogSnapshot: Equatable {
        let style: LockScreenGlassStyle
        let customizationMode: LockScreenGlassCustomizationMode
        let variantRawValue: Int
        let usesLiquidGlass: Bool
    }

    static let collapsedHeight: CGFloat = 180
    static let defaultCollapsedWidth: CGFloat = 420
    static var collapsedSize: CGSize {
        CGSize(width: CGFloat(Defaults[.lockScreenMusicPanelWidth]), height: collapsedHeight)
    }
    static let expandedSize = CGSize(width: 720, height: 340)

    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var likeController = SpotifyLikeController.shared
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @ObservedObject private var fullscreenArtworkManager = FullScreenArtworkWindowManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @ObservedObject private var animator: LockScreenPanelAnimator
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var isActive = true
    @State private var isExpanded = false
    @State private var isVolumeSliderVisible = false
    @State private var isAirPlayPopoverPresented = false
    @State private var isArtworkFullscreen = false
    
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var parallaxResumeWorkItem: DispatchWorkItem?
    @State private var isParallaxSuspended = false
    @State private var lastLoggedGlassSnapshot: GlassLogSnapshot?
    @Default(.lockScreenGlassStyle) var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var glassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var musicGlassVariant
    @Default(.lockScreenShowAppIcon) var showAppIcon
    @Default(.lockScreenPanelShowsBorder) var showPanelBorder
    @Default(.lockScreenMusicUsesEnhancedLiquidBorder) private var useEnhancedLiquidBorder
    @Default(.lockScreenPanelUsesBlur) var enableBlur
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.lockScreenMusicMergedAirPlayOutput) private var mergedAirPlayOutput
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenParallaxEnabled
    @Default(.lockScreenMusicPanelWidth) private var collapsedPanelWidth
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var fullscreenArtworkEnabled
    @Default(.lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork) private var keepAlbumArtVisibleDuringFullscreenArtwork
    @Default(.lockScreenMusicFullscreenVideoArtwork) private var fullscreenVideoArtwork

    init(animator: LockScreenPanelAnimator) {
        _animator = ObservedObject(wrappedValue: animator)
    }
    
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private let collapsedAlbumArtCornerRadius: CGFloat = 16
    private let expandedAlbumArtCornerRadius: CGFloat = 60
    private let expandedContentSpacing: CGFloat = 40
    private let collapseTimeout: TimeInterval = 5
    private let collapsedSliderExtraHeight: CGFloat = 72
    private let expandedSliderExtraHeight: CGFloat = 88
    private let collapsedLyricsExtraHeight: CGFloat = 64
    private let expandedLyricsExtraHeight: CGFloat = 96

    private var shouldUseFrostedBlur: Bool {
        enableBlur && !usesLiquidGlass
    }

    private var currentSize: CGSize {
        let base = isExpanded ? Self.expandedSize : collapsedPanelSize
        return CGSize(width: base.width, height: base.height + totalExtraHeight)
    }

    private var collapsedPanelSize: CGSize {
        CGSize(width: CGFloat(collapsedPanelWidth), height: Self.collapsedHeight)
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
    }

    private var usesCustomLiquidGlass: Bool {
        glassCustomizationMode == .customLiquid
    }

    private var usesStandardLiquidGlass: Bool {
        guard glassCustomizationMode == .standard else { return false }
        if #available(macOS 26.0, *) {
            return lockScreenGlassStyle == .liquid
        }
        return false
    }

    private var usesLiquidGlass: Bool {
        usesCustomLiquidGlass || usesStandardLiquidGlass
    }

    private var usesEnhancedCustomLiquidBorder: Bool {
        usesCustomLiquidGlass && useEnhancedLiquidBorder
    }

    private var hidesInlineArtworkForSpotifyCanvasFallback: Bool {
        fullscreenArtworkManager.isShowingSpotifyCanvasFallback
    }

    private var usesSpotifyCanvasFallbackContentPresentation: Bool {
        fullscreenArtworkManager.isShowingSpotifyCanvasFallback
    }

    private var showsDetachedFullscreenLyrics: Bool {
        usesSpotifyCanvasFallbackContentPresentation && enableLyrics
    }

    private var shouldShowInlineLyrics: Bool {
        enableLyrics && !showsDetachedFullscreenLyrics
    }
    
    var body: some View {
        if isActive && musicManager.hasActiveSession {
            panelContent
        } else {
            Color.clear
                .frame(width: collapsedPanelSize.width, height: collapsedPanelSize.height)
        }
    }
    
    private var panelContent: some View {
        ZStack(alignment: .topLeading) {
            panelBackgroundLayer
            panelForeground
                .shadow(
                    color: usesSpotifyCanvasFallbackContentPresentation ? Color.black.opacity(0.55) : .clear,
                    radius: usesSpotifyCanvasFallbackContentPresentation ? 10 : 0,
                    x: 0,
                    y: usesSpotifyCanvasFallbackContentPresentation ? 2 : 0
                )
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .overlay {
            if showPanelBorder && !usesSpotifyCanvasFallbackContentPresentation {
                panelBorderOverlay
            }
        }
        .shadow(
            color: usesSpotifyCanvasFallbackContentPresentation ? Color.black.opacity(0.35) : Color.black.opacity(0.3),
            radius: usesSpotifyCanvasFallbackContentPresentation ? 26 : 20,
            x: 0,
            y: usesSpotifyCanvasFallbackContentPresentation ? 14 : 10
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.28), value: isExpanded)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .onAppear {
            sliderValue = musicManager.elapsedTime
            isActive = true
            logPanelAppearance()
            updatePanelSize(animated: false)
            routeManager.refreshDevices()
            if isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
            logGlassState(reason: "Panel appeared")
        }
        .onDisappear {
            isActive = false
            cancelCollapseTimer()
            isVolumeSliderVisible = false
            parallaxResumeWorkItem?.cancel()
            parallaxResumeWorkItem = nil
            isParallaxSuspended = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .atollArtworkWallpaperDismissed)) { _ in
            withAnimation(.easeInOut(duration: 0.28)) {
                isArtworkFullscreen = false
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            updatePanelSize()
        }
        .onChange(of: showMediaOutputControl) { _, enabled in
            if !enabled {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    isVolumeSliderVisible = false
                }
            }
            updatePanelSize()
        }
        .onChange(of: isVolumeSliderVisible) { _, visible in
            if useMergedAirPlayOutput {
                if visible && isAppleMusicActive {
                    Task { await airPlayManager.refreshDevices() }
                }
            }
            updatePanelSize()
        }
        .onChange(of: airPlayManager.devices) { _, _ in
            if useMergedAirPlayOutput {
                updatePanelSize()
            }
        }
        .onChange(of: routeManager.devices) { _, _ in
            if !useMergedAirPlayOutput {
                updatePanelSize()
            }
        }
        .onChange(of: enableLyrics) { _, _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                updatePanelSize()
            }
        }
        .onChange(of: lockScreenGlassStyle) { _, _ in
            logGlassState(reason: "Glass style updated")
        }
        .onChange(of: glassCustomizationMode) { _, _ in
            logGlassState(reason: "Glass mode updated")
        }
        .onChange(of: musicGlassVariant) { _, _ in
            if usesCustomLiquidGlass {
                logGlassState(reason: "Liquid variant updated")
            }
        }
        .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.52, dampingFraction: 0.8), value: animator.isPresented)
    }

    @ViewBuilder
    private var panelForeground: some View {
        Group {
            if isExpanded {
                expandedLayout
            } else {
                collapsedLayout
            }
        }
        .padding(.horizontal, usesSpotifyCanvasFallbackContentPresentation ? (isExpanded ? 24 : 22) : (isExpanded ? 24 : 20))
        .padding(.vertical, usesSpotifyCanvasFallbackContentPresentation ? (isExpanded ? 18 : 14) : (isExpanded ? 22 : 16))
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: usesSpotifyCanvasFallbackContentPresentation ? .center : .topLeading
        )
    }

    private var collapsedLayout: some View {
        VStack(spacing: 12) {
            collapsedHeader
            progressBar
                .padding(.top, 4)
                .frame(maxWidth: .infinity)
            playbackControls(alignment: .center)
                .padding(.top, 4)
        }
    }

    private var expandedLayout: some View {
        Group {
            if hidesInlineArtworkForSpotifyCanvasFallback {
                VStack(alignment: .leading, spacing: 20) {
                    expandedHeader
                    progressBar
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity)
                    playbackControls(alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: expandedContentSpacing) {
                    albumArtButton(size: 230, cornerRadius: expandedAlbumArtCornerRadius)
                        .frame(width: 230, height: 230)

                    VStack(alignment: .leading, spacing: 20) {
                        expandedHeader
                        progressBar
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity)
                        playbackControls(alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: hidesInlineArtworkForSpotifyCanvasFallback ? 10 : 16) {
            if !hidesInlineArtworkForSpotifyCanvasFallback {
                albumArtButton(size: 60, cornerRadius: collapsedAlbumArtCornerRadius)
            }

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 1) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: .system(size: 12, weight: .semibold),
                        nsFont: .subheadline,
                        textColor: .white,
                        minDuration: 0.45,
                        frameWidth: geo.size.width,
                        badgeSpacing: 5,
                        badgeLabel: "E",
                        badgeHeight: 13,
                        badgeForegroundColor: Color.black.opacity(0.72),
                        badgeBackgroundColor: Color.white.opacity(0.46),
                        badgeHorizontalPadding: 4,
                        badgeMinWidth: 14,
                        badgeCornerRadius: 4
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)

            visualizer(width: 20, height: 16)
        }
        .frame(height: 60)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 6) {
                    MusicTitleMarqueeView(
                        text: musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle,
                        isExplicit: !musicManager.songTitle.isEmpty && musicManager.isCurrentTrackExplicit,
                        font: .system(size: 18, weight: .semibold),
                        nsFont: .title3,
                        textColor: .white,
                        minDuration: 0.55,
                        frameWidth: geo.size.width,
                        badgeSpacing: 6,
                        badgeLabel: "E",
                        badgeHeight: 16,
                        badgeForegroundColor: Color.black.opacity(0.74),
                        badgeBackgroundColor: Color.white.opacity(0.5),
                        badgeHorizontalPadding: 5,
                        badgeMinWidth: 17,
                        badgeCornerRadius: 5
                    )

                    Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.7) : .gray)
                        .lineLimit(2)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)

            visualizer(width: 24, height: 20)
        }
    }

    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        let artworkCornerRadius = resolvedArtworkCornerRadius(from: cornerRadius)

        return ZStack(alignment: .bottomTrailing) {
            if isArtworkFullscreen && !keepAlbumArtVisibleDuringFullscreenArtwork {
                RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Image(systemName: "photo.fill")
                            .font(.system(size: size * 0.3, weight: .light))
                            .foregroundColor(.white.opacity(0.2))
                    )
            } else {
                albumArtImage(size: size, cornerRadius: cornerRadius)
                if showAppIcon, let icon = lockScreenAppIcon {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: appIconSize, height: appIconSize)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
                        .offset(x: appIconOffset, y: appIconOffset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .albumArtFlip(angle: isArtworkFullscreen && !keepAlbumArtVisibleDuringFullscreenArtwork ? 0 : musicManager.flipAngle)
        .parallax3D(
            enableOverride: lockScreenParallaxEnabled && (!isArtworkFullscreen || keepAlbumArtVisibleDuringFullscreenArtwork),
            suspended: isParallaxSuspended
        )
        .frame(width: size)
        .background(albumArtBackground(cornerRadius: artworkCornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius, style: .continuous))
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: musicManager.isPlaying)
        .animation(.easeInOut(duration: 0.28), value: isArtworkFullscreen)
        .onTapGesture {
            toggleExpanded()
        }
        .onRightClick {
            expandArtworkToFullscreen()
        }
    }

    @ViewBuilder
    private func visualizer(width: CGFloat, height: CGFloat) -> some View {
        if Defaults[.useMusicVisualizer] {
            Rectangle()
                .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                .mask {
                    AudioVisualizerView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
        }
    }

    private func toggleExpanded() {
        let newState = !isExpanded
        suspendParallaxInteraction()
        withAnimation(.easeInOut(duration: 0.28)) {
            isExpanded = newState
        }

        if newState {
            registerInteraction()
            logPanelAppearance(event: "🔍 Expanded")
        } else {
            logPanelAppearance(event: "⬇️ Collapsed")
            cancelCollapseTimer()
        }
    }

    private func expandArtworkToFullscreen() {
        guard fullscreenArtworkEnabled else { return }

        if FullScreenArtworkWindowManager.shared.isShowing {
            FullScreenArtworkWindowManager.shared.hide()
            withAnimation(.easeInOut(duration: 0.28)) {
                isArtworkFullscreen = false
            }
            return
        }

        guard musicManager.hasActiveSession else { return }

        let artwork = musicManager.albumArt
        let videoURL = musicManager.videoArtworkURL

        withAnimation(.easeInOut(duration: 0.28)) {
            isArtworkFullscreen = true
        }

        FullScreenArtworkWindowManager.shared.onDismiss = {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.28)) {
                    NotificationCenter.default.post(name: .atollArtworkWallpaperDismissed, object: nil)
                }
            }
        }

        FullScreenArtworkWindowManager.shared.show(
            artwork: artwork,
            videoURL: fullscreenVideoArtwork ? videoURL : nil,
            allowLiveWallpaper: fullscreenVideoArtwork
        )
    }

    private func registerInteraction() {
        cancelCollapseTimer()
        guard isExpanded else { return }

        let workItem = DispatchWorkItem {
            suspendParallaxInteraction()
            withAnimation(.easeInOut(duration: 0.28)) {
                isExpanded = false
            }
            logPanelAppearance(event: "⏱️ Auto-collapsed")
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseTimeout, execute: workItem)
    }

    private func suspendParallaxInteraction(for duration: TimeInterval = 0.65) {
        parallaxResumeWorkItem?.cancel()
        isParallaxSuspended = true

        let workItem = DispatchWorkItem {
            isParallaxSuspended = false
        }
        parallaxResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0,
                paused: isProgressTimelinePaused
            )
        ) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: Binding(
                    get: { musicManager.songDuration },
                    set: { musicManager.songDuration = $0 }
                ),
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream,
                onValueChange: { newValue in
                    registerInteraction()
                    musicManager.seek(to: newValue)
                },
                labelLayout: .inline,
                trailingLabel: .remaining,
                restingTrackHeight: 7,
                draggingTrackHeight: 11
            )
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
        .onChange(of: musicManager.isLiveStream) { _, isLive in
            if isLive {
                dragging = false
                sliderValue = 0
            }
        }
    }

    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .white:
            return .white
        case .albumArt:
            return Color(nsColor: musicManager.avgColor)
        case .accent:
            return .accentColor
        }
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }
    
    // MARK: - Playback Controls
    
    private func playbackControls(alignment: Alignment) -> some View {
        let spacing: CGFloat = isExpanded ? 24 : 20
        let verticalSpacing: CGFloat = (shouldShowVolumeSlider || shouldShowInlineLyrics) ? 14 : 10

        return VStack(spacing: verticalSpacing) {
            controlsRow(alignment: alignment, spacing: spacing)

            if shouldShowVolumeSlider {
                volumeSlider
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))

                if shouldShowAirPlay {
                    airPlaySection
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                } else if shouldShowRouteSelector {
                    mediaOutputDevicesSection
                        .frame(maxWidth: .infinity, alignment: alignment)
                        .transition(.scale(scale: 0.98, anchor: .top).combined(with: .opacity))
                }
            }

            if shouldShowInlineLyrics {
                lyricsSection(alignment: alignment)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.top, isExpanded ? 6 : 2)
        .animation(.easeInOut(duration: 0.24), value: shouldShowVolumeSlider)
        .animation(.easeInOut(duration: 0.24), value: shouldShowAirPlay)
        .animation(.easeInOut(duration: 0.24), value: shouldShowRouteSelector)
        .animation(.easeInOut(duration: 0.24), value: enableLyrics)
    }

    private func controlsRow(alignment: Alignment, spacing: CGFloat) -> some View {
        let skipNudge: CGFloat = isExpanded ? 14 : 9

        return HStack(spacing: spacing) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot, skipNudge: skipNudge)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
    
    private var displayedSlots: [MusicControlButton] {
        guard showShuffleAndRepeat else {
            return fallbackSlots
        }

        let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: isAppleMusicActive)
        return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
    }

    private var fallbackSlots: [MusicControlButton] {
        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton, skipNudge: CGFloat) -> some View {
        let seekInterval: TimeInterval = 10

        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            playPauseButton
        case .trackBackward:
            controlButton(
                icon: "backward.fill",
                size: 18,
                interaction: .nudge(-skipNudge),
                symbolEffect: .replace
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            controlButton(
                icon: "forward.fill",
                size: 18,
                interaction: .nudge(skipNudge),
                symbolEffect: .replace
            ) {
                musicManager.nextTrack()
            }
        case .seekBackward:
            controlButton(
                icon: "gobackward.10",
                size: 18,
                interaction: .wiggle(.counterClockwise),
                symbolEffect: .wiggle
            ) {
                musicManager.seek(by: -seekInterval)
            }
        case .seekForward:
            controlButton(
                icon: "goforward.10",
                size: 18,
                interaction: .wiggle(.clockwise),
                symbolEffect: .wiggle
            ) {
                musicManager.seek(by: seekInterval)
            }
        case .shuffle:
            controlButton(
                icon: "shuffle",
                size: 18,
                isActive: musicManager.isShuffled,
                activeColor: brandAccentColor
            ) {
                musicManager.toggleShuffle()
            }
        case .repeatMode:
            controlButton(
                icon: repeatIcon,
                size: 18,
                isActive: musicManager.repeatMode != .off,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                musicManager.toggleRepeat()
            }
        case .mediaOutput:
            mediaOutputControlButton
        case .airPlay:
            if useMergedAirPlayOutput {
                mediaOutputControlButton
            } else {
                standaloneAirPlayButton
            }
        case .lyrics:
            controlButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                size: 18,
                isActive: enableLyrics,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    enableLyrics.toggle()
                }
            }
        case .like:
            controlButton(
                icon: likeController.isLiked ? "heart.fill" : "heart",
                size: 18,
                isActive: likeController.isLiked,
                activeColor: brandAccentColor,
                symbolEffect: .replace
            ) {
                likeController.toggle()
            }
            .opacity(likeController.canLike ? 1 : 0.35)
            .disabled(!likeController.canLike)
        }
    }

    private var playPauseButton: some View {
        let frameSize: CGFloat = isExpanded ? 80 : 54
        let iconName = musicManager.isPlaying ? "pause.fill" : "play.fill"

        return HoverButton(
            icon: iconName,
            iconColor: .white,
            scale: .large,
            pressEffect: nil
        ) {
            registerInteraction()
            musicManager.togglePlay()
        }
        .frame(width: frameSize, height: frameSize)
    }
    
    private func controlButton(
        icon: String,
        size: CGFloat = 18,
        isActive: Bool = false,
        activeColor: Color? = nil,
        interaction: PanelControlButton.Interaction = .none,
        symbolEffect: PanelControlButton.SymbolEffectStyle = .replace,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedActiveColor = activeColor ?? brandAccentColor
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? max(size, 24) : size
        let iconColor = isActive ? resolvedActiveColor : .white.opacity(0.8)
        let backgroundOpacity: Double = isActive ? 0.22 : 0.0

        return PanelControlButton(
            icon: icon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: iconColor,
            backgroundOpacity: backgroundOpacity,
            interaction: interaction,
            symbolEffect: symbolEffect
        ) {
            registerInteraction()
            action()
        }
    }
    
    private var mediaOutputControlButton: some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? 26 : 18

        return PanelControlButton(
            icon: mediaOutputIcon,
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: shouldShowVolumeSlider ? .accentColor : .white.opacity(0.8),
            backgroundOpacity: shouldShowVolumeSlider ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace,
            action: toggleVolumeSlider
        )
        .accessibilityLabel("Media output")
    }

    private var standaloneAirPlayButton: some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? 26 : 18

        return PanelControlButton(
            icon: "airplayaudio",
            frameSize: frameSize,
            iconSize: iconSize,
            iconColor: isAirPlayPopoverPresented ? .accentColor : .white.opacity(0.8),
            backgroundOpacity: isAirPlayPopoverPresented ? 0.22 : 0.0,
            interaction: .none,
            symbolEffect: .replace
        ) {
            registerInteraction()
            isAirPlayPopoverPresented.toggle()
            if isAirPlayPopoverPresented {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .accessibilityLabel("AirPlay")
        .popover(isPresented: $isAirPlayPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { _ in },
                dismiss: { isAirPlayPopoverPresented = false }
            )
        }
    }

    private func lyricsSection(alignment: Alignment) -> some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        let transition: AnyTransition = .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )

        return HStack(spacing: 8) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                Text(line)
                    .font(.system(size: isExpanded ? 14 : 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .id(line)
                    .transition(transition)
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 8)
        .padding(.top, isExpanded ? 12 : 8)
        .frame(maxWidth: .infinity, alignment: alignment)
        .animation(.smooth(duration: 0.32), value: line)
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var mediaOutputIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private var volumeSlider: some View {
        HStack(spacing: 14) {
            Image(systemName: volumeIconName)
                .font(.system(size: isExpanded ? 16 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Slider(
                value: Binding(
                    get: { Double(volumeModel.level) },
                    set: { newValue in
                        registerInteraction()
                        volumeModel.setVolume(Float(newValue))
                    }
                ),
                in: 0 ... 1
            )
            .tint(sliderColor)

            Text(volumePercentage)
                .font(.system(size: isExpanded ? 12 : 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                .fill(sliderBackgroundFill)
        )
    }

    private var airPlaySection: some View {
        accessorySectionContainer {
            if airPlayManager.devices.isEmpty {
                Text("No AirPlay outputs available")
                    .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    registerInteraction()
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                        Text(device.name)
                                            .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: isExpanded ? 12 : 10, weight: .bold))
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: accessorySectionScrollMaxHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private var mediaOutputDevicesSection: some View {
        accessorySectionContainer {
            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                registerInteraction()
                                routeManager.select(device: device)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: isExpanded ? 14 : 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.82))
                                    Text(device.name)
                                        .font(.system(size: isExpanded ? 13 : 11, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: isExpanded ? 12 : 10, weight: .bold))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: accessorySectionScrollMaxHeight)
            }
        }
        .padding(.vertical, 8)
    }

    private func accessorySectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: isExpanded ? 16 : 12, style: .continuous)
                    .fill(sliderBackgroundFill)
            )
    }

    private var sliderBackgroundFill: Color {
        if usesLiquidGlass {
            return Color.white.opacity(0.05)
        }
        return Color.white.opacity(0.08)
    }

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private var useMergedAirPlayOutput: Bool {
        mergedAirPlayOutput && isAppleMusicActive && slotConfig.contains(where: { $0 == .mediaOutput || $0 == .airPlay })
    }

    private var shouldShowAirPlay: Bool {
        useMergedAirPlayOutput && shouldShowVolumeSlider && !airPlayManager.devices.isEmpty
    }

    private var shouldShowRouteSelector: Bool {
        !useMergedAirPlayOutput && shouldShowVolumeSlider
    }

    private var shouldShowAccessorySection: Bool {
        shouldShowAirPlay || shouldShowRouteSelector
    }

    private var shouldShowVolumeSlider: Bool {
        showMediaOutputControl && isVolumeSliderVisible
    }

    private var sliderExtraHeight: CGFloat {
        sliderHeight(forExpanded: isExpanded, visible: shouldShowVolumeSlider)
    }

    private var accessorySectionScrollMaxHeight: CGFloat {
        isExpanded ? 170 : 130
    }

    private var lyricsExtraHeight: CGFloat {
        lyricsHeight(forExpanded: isExpanded, enabled: shouldShowInlineLyrics)
    }

    private var accessorySectionExtraHeight: CGFloat {
        guard shouldShowAccessorySection else { return 0 }
        if shouldShowAirPlay {
            let selectedCount = airPlayManager.devices.filter(\.isSelected).count
            let totalCount = airPlayManager.devices.count
            let deviceRows: CGFloat = CGFloat(totalCount) * 30 + CGFloat(max(totalCount - 1, 0)) * 6
            let sliders: CGFloat = CGFloat(selectedCount) * 34
            return min(deviceRows + sliders + 24, accessorySectionScrollMaxHeight + 16)
        }

        let totalCount = max(routeManager.devices.count, 1)
        let deviceRows: CGFloat = CGFloat(totalCount) * 30 + CGFloat(max(totalCount - 1, 0)) * 6
        return min(deviceRows + 24, accessorySectionScrollMaxHeight + 16)
    }

    private var totalExtraHeight: CGFloat {
        sliderExtraHeight + accessorySectionExtraHeight + lyricsExtraHeight
    }

    private func lyricsHeight(forExpanded expanded: Bool, enabled: Bool) -> CGFloat {
        guard enabled else { return 0 }
        return expanded ? expandedLyricsExtraHeight : collapsedLyricsExtraHeight
    }

    private func panelAdditionalHeight(forExpanded expanded: Bool) -> CGFloat {
        sliderHeight(forExpanded: expanded, visible: shouldShowVolumeSlider) +
        accessorySectionExtraHeight +
        lyricsHeight(forExpanded: expanded, enabled: shouldShowInlineLyrics)
    }

    private func updatePanelSize(animated: Bool = true) {
        LockScreenPanelManager.shared.updatePanelSize(
            expanded: isExpanded,
            additionalHeight: panelAdditionalHeight(forExpanded: isExpanded),
            animated: animated
        )
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }

    private func toggleVolumeSlider() {
        guard showMediaOutputControl else {
            isVolumeSliderVisible = false
            return
        }

        registerInteraction()
        let newState = !isVolumeSliderVisible
        if newState {
            routeManager.refreshDevices()
            if useMergedAirPlayOutput {
                Task { await airPlayManager.refreshDevices() }
            }
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            isVolumeSliderVisible = newState
        }

        updatePanelSize()
    }

    private func sliderHeight(forExpanded expanded: Bool, visible: Bool) -> CGFloat {
        guard visible else { return 0 }
        return expanded ? expandedSliderExtraHeight : collapsedSliderExtraHeight
    }

    @ViewBuilder
    private var panelBackgroundLayer: some View {
        if usesSpotifyCanvasFallbackContentPresentation {
            canvasFallbackScrim
        } else if usesCustomLiquidGlass {
            customLiquidPanelBackdrop
        } else if usesStandardLiquidGlass {
            standardLiquidPanelBackdrop
        } else if shouldUseFrostedBlur {
            frostedPanelBackground
        } else {
            opaquePanelBackground
        }
    }

    private var canvasFallbackScrim: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.32),
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.32)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var standardLiquidPanelBackdrop: some View {
        if #available(macOS 26.0, *) {
            GlassTextBackdrop(cornerRadius: panelCornerRadius)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var customLiquidPanelBackdrop: some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: panelCornerRadius) {
            Color.white.opacity(0.04)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var frostedPanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(.ultraThinMaterial)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var opaquePanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(Color.black.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var panelBorderOverlay: some View {
        if usesEnhancedCustomLiquidBorder {
            ZStack {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.22),
                        lineWidth: 1.05
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.1),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )

                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .inset(by: 1.55)
                    .stroke(
                        Color.black.opacity(0.16),
                        lineWidth: 0.55
                    )
            }
            .allowsHitTesting(false)
        } else if usesLiquidGlass {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(
                    Color.white.opacity(usesCustomLiquidGlass ? 0.15 : 0.14),
                    lineWidth: usesCustomLiquidGlass ? 0.95 : 0.9
                )
                .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
                .allowsHitTesting(false)
        }
    }

    private func albumArtImage(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: resolvedArtworkCornerRadius(from: cornerRadius), style: .continuous))
    }

    @ViewBuilder
    private func albumArtBackground(cornerRadius: CGFloat) -> some View {
        if usesCustomLiquidGlass {
            customLiquidAlbumArtBackground(cornerRadius: cornerRadius)
        } else if usesStandardLiquidGlass {
            if #available(macOS 26.0, *) {
                clearLiquidGlassSurface(cornerRadius: cornerRadius)
            }
        } else if shouldUseFrostedBlur {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.35))
        }
    }

    private var lockScreenAppIcon: Image? {
        guard showAppIcon, !musicManager.usingAppIconForArtwork else { return nil }
        let bundleIdentifier = musicManager.bundleIdentifier ?? "com.apple.Music"
        return AppIcon(for: bundleIdentifier)
    }

    private var appIconSize: CGFloat {
        isExpanded ? 58 : 34
    }

    private var appIconCornerRadius: CGFloat {
        isExpanded ? 18 : 12
    }

    private var appIconOffset: CGFloat {
        isExpanded ? 18 : 12
    }

    private func resolvedArtworkCornerRadius(from baseCornerRadius: CGFloat) -> CGFloat {
        let aspectRatio = musicManager.albumArt.size.height > 0
            ? musicManager.albumArt.size.width / musicManager.albumArt.size.height
            : 1
        return aspectRatio > 1.0 ? baseCornerRadius / 3 : baseCornerRadius
    }

    @available(macOS 26.0, *)
    private func clearLiquidGlassSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.clear)
            .glassEffect(
                .clear.interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
    }

    @ViewBuilder
    private func customLiquidAlbumArtBackground(cornerRadius: CGFloat) -> some View {
        LiquidGlassBackground(variant: musicGlassVariant, cornerRadius: cornerRadius) {
            Color.clear
        }
    }

    private func logGlassState(reason: String) {
        let snapshot = GlassLogSnapshot(
            style: lockScreenGlassStyle,
            customizationMode: glassCustomizationMode,
            variantRawValue: musicGlassVariant.rawValue,
            usesLiquidGlass: usesLiquidGlass
        )
        guard snapshot != lastLoggedGlassSnapshot else { return }
        lastLoggedGlassSnapshot = snapshot

        struct ComponentState {
            let name: String
            let isLiquid: Bool
        }

        let states = [
            ComponentState(name: "Panel Shell", isLiquid: usesLiquidGlass),
            ComponentState(name: "Control Capsules", isLiquid: usesLiquidGlass),
            ComponentState(name: "Volume Slider", isLiquid: usesLiquidGlass),
            ComponentState(name: "Album Art Plate", isLiquid: usesLiquidGlass)
        ]

        let componentSummary = states.map { entry -> String in
            let mode = entry.isLiquid ? "Liquid" : "Frosted"
            return "\(entry.name)=\(mode)"
        }.joined(separator: ", ")

        let modeDescription: String
        if usesCustomLiquidGlass {
            modeDescription = "Custom Liquid (variant \(musicGlassVariant.rawValue))"
        } else if usesStandardLiquidGlass {
            modeDescription = "Standard Liquid"
        } else {
            modeDescription = lockScreenGlassStyle.rawValue
        }

        print("[LockScreenMusicPanel] \(reason) – customization=\(glassCustomizationMode.rawValue), mode=\(modeDescription), components[\(componentSummary)], macOS \(currentOSVersionDescription())")

        if glassCustomizationMode == .standard && lockScreenGlassStyle == .liquid && !usesStandardLiquidGlass {
            print("[LockScreenMusicPanel] Liquid Glass requested but unavailable on this macOS build. Falling back to frosted visuals.")
        }
    }

    private func currentOSVersionDescription() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func logPanelAppearance(event: String = "✅ View appeared") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let styleDescriptor = usesLiquidGlass ? "Liquid Glass" : "Frosted"
        print("[\(formatter.string(from: Date()))] LockScreenMusicPanel: \(event) – \(styleDescriptor)")
    }
}

private struct PanelControlButton: View {
    let icon: String
    let frameSize: CGFloat
    let iconSize: CGFloat
    let iconColor: Color
    let backgroundOpacity: Double
    let interaction: Interaction
    let symbolEffect: SymbolEffectStyle
    let action: () -> Void

    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @State private var wiggleToken: Int = 0

    var body: some View {
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            RoundedRectangle(cornerRadius: frameSize / 2, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    iconView
                )
        }
        .frame(width: frameSize, height: frameSize)
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(rotationAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.24)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        let hoveredOpacity = max(backgroundOpacity + 0.08, 0.18)
        let appliedOpacity = isHovering ? hoveredOpacity : backgroundOpacity
        return Color.white.opacity(min(appliedOpacity, 0.32))
    }

    private func triggerPressEffect() {
        switch interaction {
        case .none:
            return
        case .nudge(let amount):
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressOffset = amount
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                rotationAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    rotationAngle = 0
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        let base = Image(systemName: icon)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(iconColor)

        switch symbolEffect {
        case .replace:
            base.contentTransition(.symbolEffect(.replace))
        case .replaceAndBounce:
            if #available(macOS 14.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: icon)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        case .wiggle:
            if #available(macOS 15.0, *) {
                base
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: wiggleToken)
            } else {
                base.contentTransition(.symbolEffect(.replace))
            }
        }
    }

    enum Interaction {
        case none
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum SymbolEffectStyle {
        case replace
        case replaceAndBounce
        case wiggle
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}

@available(macOS 26.0, *)
private struct GlassTextBackdrop: View {
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let dynamicFontSize = max(min(proxy.size.width, proxy.size.height) / 8, 42)

            Text("Lock Screen Liquid Glass")
                .font(.system(size: dynamicFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.clear)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .glassEffect(
                    .clear.interactive(),
                    in: .rect(cornerRadius: cornerRadius)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Right Click Gesture

private struct RightClickOverlay: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(
            RightClickReceiverView(action: action)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

private struct RightClickReceiverView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickNSView {
        let view = RightClickNSView()
        view.onRightClick = action
        return view
    }

    func updateNSView(_ nsView: RightClickNSView, context: Context) {
        nsView.onRightClick = action
    }
}

private extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        modifier(RightClickOverlay(action: action))
    }
}

final class RightClickNSView: NSView {
    var onRightClick: (() -> Void)?
    private var eventMonitor: Any?

    deinit {
        removeEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeEventMonitor()
        } else {
            installEventMonitorIfNeeded()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            let pointInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(pointInView) else {
                return event
            }

            self.onRightClick?()
            return nil
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

extension Notification.Name {
    static let atollArtworkWallpaperDismissed = Notification.Name("atollArtworkWallpaperDismissed")
}
