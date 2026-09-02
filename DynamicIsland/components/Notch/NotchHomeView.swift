/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Combine
import Defaults
import SwiftUI
import AppKit
import AVFoundation

private final class DynamicIslandArtworkLoopController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var playbackStateCancellable: AnyCancellable?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)

        if MusicManager.shared.isPlaying {
            player.play()
        }

        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
    }

    deinit {
        player.pause()
        looper = nil
        playbackStateCancellable = nil
    }
}

private final class DynamicIslandArtworkVideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // SwiftUI owns the enclosing transition timing. Prevent the video
        // layer from adding a second implicit frame animation during that
        // transition, which makes Canvas artwork lag behind static artwork.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct DynamicIslandArtworkVideoView: NSViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DynamicIslandArtworkVideoContainerView {
        let view = DynamicIslandArtworkVideoContainerView(frame: .zero)
        context.coordinator.attach(layer: view.playerLayer, url: url, gravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: DynamicIslandArtworkVideoContainerView, context: Context) {
        context.coordinator.attach(layer: nsView.playerLayer, url: url, gravity: videoGravity)
    }

    final class Coordinator {
        private var controller: DynamicIslandArtworkLoopController?
        private var currentURL: URL?

        func attach(layer: AVPlayerLayer, url: URL, gravity: AVLayerVideoGravity) {
            layer.videoGravity = gravity

            if currentURL != url || controller == nil {
                currentURL = url
                controller = DynamicIslandArtworkLoopController(url: url)
            }

            if layer.player !== controller?.player {
                layer.player = controller?.player
            }
        }
    }
}

struct DynamicIslandArtworkSourceView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland

    let cornerRadius: CGFloat
    let contentMode: ContentMode

    private var liveCanvasURL: URL? {
        guard showLiveCanvasInDynamicIsland else { return nil }
        return musicManager.videoArtworkURL
    }

    var body: some View {
        Group {
            if let liveCanvasURL {
                DynamicIslandArtworkVideoView(url: liveCanvasURL, videoGravity: .resizeAspectFill)
            } else {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
            MusicControlsView()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LyricsSidePanelView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    private var artistLineColor: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    /// The colour a line has yet to be sung in. Tinted rather than plain grey so
    /// the unsung remainder still reads as part of the current line.
    private var lyricsStyle: SyncedLyricsStyle {
        SyncedLyricsStyle(
            sung: .white,
            unsung: artistLineColor.opacity(0.55),
            idle: .white.opacity(0.5),
            tint: artistLineColor
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lyrics")
                .font(.headline)
                .foregroundStyle(artistLineColor)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            SyncedLyricsList(musicManager: musicManager, style: lyricsStyle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
        .onDisappear {
            updateSuppression(for: false)
        }
    }

    // Prevent lyrics scrolling to close the expanded notch
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland
    let albumArtNamespace: Namespace.ID

    private var usesLiveCanvasArtwork: Bool {
        showLiveCanvasInDynamicIsland && musicManager.videoArtworkURL != nil
    }

    private var albumArtCornerRadius: CGFloat {
        Defaults[.cornerRadiusScaling]
            ? musicManager.albumArt.size.width / musicManager.albumArt.size.height > 1.0
                ? MusicPlayerImageSizes.cornerRadiusInset.opened / 3
                : MusicPlayerImageSizes.cornerRadiusInset.opened
            : musicManager.albumArt.size.width / musicManager.albumArt.size.height > 1.0
                ? MusicPlayerImageSizes.cornerRadiusInset.closed / 3
                : MusicPlayerImageSizes.cornerRadiusInset.closed
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(
                DynamicIslandArtworkSourceView(
                    cornerRadius: albumArtCornerRadius,
                    contentMode: .fill
                )
            )
            .clipped()
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(
                usesLiveCanvasArtwork
                    ? (musicManager.isPlaying ? 0.62 : 0.18)
                    : (musicManager.isPlaying ? 0.5 : 0)
            )
            .shadow(
                color: Color(nsColor: musicManager.avgColor).opacity(usesLiveCanvasArtwork ? 0.24 : 0.16),
                radius: usesLiveCanvasArtwork ? 22 : 14,
                x: 0,
                y: 0
            )
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
                .albumArtFlip(angle: musicManager.flipAngle)
                .parallax3D()
                .padding(.bottom, -5)

            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }

    private var albumArtImage: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                DynamicIslandArtworkSourceView(
                    cornerRadius: albumArtCornerRadius,
                    contentMode: .fit
                )
            }
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        .clipped()
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var hudValue: Double = 0
    @State private var hudDragging: Bool = false
    @State private var hudLastDragged: Date = .distantPast
    @Default(.showShuffleAndRepeat) private var showCustomControls
    @Default(.musicControlSlots) private var slotConfig
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.enableLyrics) private var enableLyrics
    @Default(.showCalendar) private var showCalendar
    private let seekInterval: TimeInterval = 10

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            if shouldShowControlHUDRow {
                controlHUDRow
            } else {
                playbackControls
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                    .zIndex(1) // Ensure it draws above the waveform scrubber
                musicSlider
                    .zIndex(0)
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicTitleMarqueeView(
                text: musicManager.songTitle,
                isExplicit: musicManager.isCurrentTrackExplicit,
                font: .headline,
                nsFont: .headline,
                textColor: .white,
                frameWidth: width,
                badgeHeight: 14
            )
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor)
                    .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if enableLyrics && showCalendar {
                let transition = AnyTransition.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )

                let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                let isInstrumentalBreak = musicManager.isInInstrumentalBreak

                if isInstrumentalBreak {
                    // The track is between verses, so mark it the way the side
                    // panel does instead of leaving a hole in the layout. Driven
                    // by the break itself rather than by the line being blank:
                    // during an intro there is no current line to blank out, so
                    // testing the text would miss it.
                    InstrumentalBreakNotes(fontSize: 10, weight: .regular)
                        .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 2)
                    .transition(transition)
                }

                if !isInstrumentalBreak, !line.isEmpty {
                    let lyricsBinding = Binding<String>(
                        get: { musicManager.currentLyrics },
                        set: { _ in }
                    )

                    MarqueeText(
                        lyricsBinding,
                        font: .system(size: 12, weight: .regular),
                        nsFont: .headline,
                        textColor: .white.opacity(0.7),
                        minDuration: 0.35,
                        frameWidth: width
                    )
                    .padding(.top, 2)
                    .id(line)
                    .transition(transition)
                    .animation(.easeInOut(duration: 0.32), value: line)
                }
            }
        }
    }

    /// Whether the progress timeline should be paused (no ticks).
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    private var musicSlider: some View {
        TimelineView(.animation(paused: isProgressTimelinePaused)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream
            ) { newValue in
                guard !musicManager.isLiveStream else { return }
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var shouldShowControlHUDRow: Bool {
        guard vm.notchState == .open else { return false }
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.enableSystemHUD] else { return false }
        guard !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] else { return false }

        switch coordinator.sneakPeek.type {
        case .volume:
            return Defaults[.enableVolumeHUD]
        case .brightness:
            return Defaults[.enableBrightnessHUD]
        case .backlight:
            return Defaults[.enableKeyboardBacklightHUD]
        default:
            return false
        }
    }

    private var controlHUDRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if !controlLeftIconName.isEmpty {
                Image(systemName: controlLeftIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }

            controlHUDSlider

            if !controlRightIconName.isEmpty {
                Image(systemName: controlRightIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { syncHUDValueIfNeeded(force: true) }
        .onChange(of: coordinator.sneakPeek.value) { _, _ in
            syncHUDValueIfNeeded(force: false)
        }
    }

    private var controlHUDSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CustomSlider(
                value: Binding(
                    get: { hudValue },
                    set: { newValue in
                        hudValue = newValue
                        updateControlHUDValue(newValue)
                    }
                ),
                range: 0...1,
                color: .white,
                dragging: $hudDragging,
                lastDragged: $hudLastDragged,
                onValueChange: { newValue in
                    updateControlHUDValue(newValue)
                },
                thumbSize: 10,
                restingTrackHeight: 4,
                draggingTrackHeight: 7
            )
            .frame(height: 7)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func syncHUDValueIfNeeded(force: Bool) {
        guard shouldShowControlHUDRow else { return }
        guard force || !hudDragging else { return }

        let target = Double(coordinator.sneakPeek.value)
        guard target != hudValue else { return }

        guard !force else {
            // First sync when the row appears: adopt the current level outright
            // rather than sliding up to it from wherever the slider last sat.
            hudValue = target
            return
        }

        // The keys deliver discrete steps (1/16 of the range each), and nothing
        // animated the fill between them, so the track jumped. Glide instead —
        // short enough to keep up with key auto-repeat, and interruptible, so a
        // held key reads as one continuous sweep rather than a queue of hops.
        withAnimation(.easeOut(duration: 0.18)) {
            hudValue = target
        }
    }

    private func updateControlHUDValue(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        switch coordinator.sneakPeek.type {
        case .volume:
            SystemVolumeController.shared.setVolume(Float(clamped))
        case .brightness:
            SystemBrightnessController.shared.setBrightness(Float(clamped))
        case .backlight:
            SystemKeyboardBacklightController.shared.setLevel(Float(clamped))
        default:
            break
        }
    }

    private var controlLeftIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness:
            return "sun.min.fill"
        case .backlight:
            return "light.min"
        default:
            return ""
        }
    }

    private var controlRightIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "" : "speaker.wave.3"
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "light.max"
        default:
            return ""
        }
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .white
        case .all, .one:
            return brandAccentColor
        }
    }

    private var displayedSlots: [MusicControlButton] {
        if showCustomControls {
            let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, canFavorite: musicManager.activeSourceCanEverFavorite)
            return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
        }

        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            HoverButton(
                icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
                scale: .large
            ) {
                MusicManager.shared.togglePlay()
            }
        case .trackBackward:
            playbackButton(
                icon: "backward.fill",
                press: nil,
                trigger: skipGestureTrigger(for: .trackBackward),
                skipDirection: .backward
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            playbackButton(
                icon: "forward.fill",
                press: nil,
                trigger: skipGestureTrigger(for: .trackForward),
                skipDirection: .forward
            ) {
                musicManager.nextTrack()
            }
        case .seekBackward:
            playbackButton(
                icon: "gobackward.10",
                press: .wiggle(.counterClockwise),
                trigger: skipGestureTrigger(for: .seekBackward)
            ) {
                musicManager.seek(by: -seekInterval)
            }
        case .seekForward:
            playbackButton(
                icon: "goforward.10",
                press: .wiggle(.clockwise),
                trigger: skipGestureTrigger(for: .seekForward)
            ) {
                musicManager.seek(by: seekInterval)
            }
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? brandAccentColor : .white,
                scale: .medium
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .repeatMode:
            HoverButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                scale: .medium
            ) {
                MusicManager.shared.toggleRepeat()
            }
        case .mediaOutput:
            MediaOutputPickerButton()
        case .airPlay:
            AirPlayPickerButton()
        case .lyrics:
            HoverButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                iconColor: enableLyrics ? brandAccentColor : .white,
                scale: .medium
            ) {
                enableLyrics.toggle()
            }
        case .likeTrack:
            LikeTrackControl { presentation, toggle in
                HoverButton(
                    icon: presentation.iconName,
                    iconColor: presentation.isActive ? brandAccentColor : .white,
                    scale: .medium
                ) {
                    toggle()
                }
            }
        }
    }

    private struct SkipTrigger {
        let token: Int
        /// nil for the track buttons: the pulse advances the skip glyph rather
        /// than moving the button.
        let pressEffect: HoverButton.PressEffect?
    }

    private func playbackButton(
        icon: String,
        press: HoverButton.PressEffect?,
        trigger: SkipTrigger?,
        skipDirection: SkipTrackGlyph.Direction? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HoverButton(
            icon: icon,
            scale: .medium,
            pressEffect: press,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect,
            skipDirection: skipDirection
        ) {
            action()
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: nil)
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: nil)
        case .seekBackward where pulse.behavior == .tenSecond && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.counterClockwise))
        case .seekForward where pulse.behavior == .tenSecond && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.clockwise))
        default:
            return nil
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.showCalendar) private var showCalendar
    @Default(.enableLyrics) private var enableLyrics
    @Default(.lyricsPanelWidth) private var lyricsPanelWidth
    @Default(.lyricsPanelOffset) private var lyricsPanelOffset
    let albumArtNamespace: Namespace.ID

    /// Whether the music player should actively display (enabled AND has real content).
    private var shouldShowMusicPlayer: Bool {
        showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession)
    }

    private var shouldShowSideLyrics: Bool {
        shouldShowMusicPlayer && enableLyrics && !showCalendar
    }
    
    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }

    private var mainContent: some View {
        Group {
            if Defaults[.enableMinimalisticUI] {
                if let overridePayload = minimalisticOverridePayload {
                    ExtensionMinimalisticExperienceView(
                        payload: overridePayload,
                        albumArtNamespace: albumArtNamespace
                    )
                } else {
                    MinimalisticMusicPlayerView(albumArtNamespace: albumArtNamespace)
                }
            } else if shouldShowSideLyrics {
                sideLyricsContent
            } else {
                HStack(alignment: .top, spacing: SideLyricsLayout.hStackSpacing) {
                    // Normal mode: Show full music player with optional calendar and webcam
                    if shouldShowMusicPlayer {
                        MusicPlayerView(albumArtNamespace: albumArtNamespace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showCalendar {
                        Group {
                            if shouldShowMusicPlayer {
                                CalendarView()
                            } else {
                                StandaloneCalendarView()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onHover { isHovering in
                            vm.isHoveringCalendar = isHovering
                        }
                        .environmentObject(vm)
                    }

                    if mirrorIsVisible {
                        cameraPreview
                    }
                }
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
            .combined(with: .move(edge: .top)))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        .padding(Defaults[.enableMinimalisticUI] ? 0 : 8) //Putting the main padding for home view here for consistency
    }

    private var sideLyricsContent: some View {
        HStack(alignment: .top, spacing: SideLyricsLayout.hStackSpacing) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)
                .frame(minWidth: SideLyricsLayout.minimumPlayerWidth, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            LyricsSidePanelView()
                .frame(width: max(0, lyricsPanelWidth), alignment: .topLeading)
                .padding(.leading, max(0, -lyricsPanelOffset))
                .offset(x: lyricsPanelOffset)

            if mirrorIsVisible {
                cameraPreview
                    .frame(minWidth: SideLyricsLayout.minimumMirrorWidth, maxWidth: .infinity)
            }
        }
    }

    private var mirrorIsVisible: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.notchState == .open
    }

    private var cameraPreview: some View {
        CameraPreviewView(webcamManager: webcamManager)
            .scaledToFit()
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
    }

    private var minimalisticOverridePayload: ExtensionNotchExperiencePayload? {
        extensionNotchExperienceManager.minimalisticReplacementPayload()
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isLiveStream: Bool
    var onValueChange: (Double) -> Void
    var labelLayout: TimeLabelLayout = .stacked
    var trailingLabel: TrailingLabel = .duration
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// When set, bypasses Defaults[.sliderColor] (used by lock screen appearance).
    var tintOverride: Color? = nil
    /// Greys the track out until it is reached for, the way Apple's transport
    /// sliders do. Opt-in: the notch's own slider is meant to carry the album
    /// colour at rest.
    var desaturatesWhenIdle: Bool = false

    enum TimeLabelLayout {
        case stacked
        case inline
    }

    enum TrailingLabel {
        case duration
        case remaining
    }

    var body: some View {
        Group {
            if isLiveStream {
                liveStreamView
            } else {
                switch labelLayout {
                case .stacked:
                    stackedContent
                case .inline:
                    inlineContent
                }
            }
        }
        .onAppear {
            guard !isLiveStream else { return }
            guard !dragging else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition())
        }
        .onChange(of: currentDate) { newDate in
            guard !isLiveStream else { return }
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition(at: newDate))
        }
        .onChange(of: isPlaying) { _, playing in
            // Snap slider to the exact position when music pauses so
            // the in-flight animation doesn't coast past the true value.
            if !playing {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
        }
        .onChange(of: isLiveStream) { isLive in
            if isLive {
                sliderValue = 0
            }
        }
    }

    private func setSliderValueWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }

    private var stackedContent: some View {
        VStack(spacing: 6) {
            sliderCore
                .frame(height: sliderFrameHeight)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
        }
    }

    private var inlineContent: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 36, alignment: .leading)

            sliderCore
                .frame(height: sliderFrameHeight)
                .frame(maxWidth: .infinity)

            Text(trailingTimeText)
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveStreamView: some View {
        switch labelLayout {
        case .stacked:
            LiveStreamProgressIndicator(tint: sliderTint)
                .frame(maxWidth: .infinity)
                .frame(height: sliderFrameHeight)
                
        case .inline:
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 36)
                LiveStreamProgressIndicator(tint: sliderTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderFrameHeight)

                Spacer()
                    .frame(width: 42)
            }
        }
    }

    @ViewBuilder
    private var sliderCore: some View {
        if hasUsableDuration {
            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: sliderTint,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange,
                restingTrackHeight: restingTrackHeight,
                draggingTrackHeight: draggingTrackHeight,
                desaturatesWhenIdle: desaturatesWhenIdle
            )
        } else {
            // `0 ... duration` traps when the upper bound is below the lower
            // one, so a negative duration crashes here before any of the
            // formatting guards get a look at it. A length nobody has reported
            // also has nothing to scrub within, so the track is inert.
            Capsule(style: .continuous)
                .fill(sliderTint.opacity(0.18))
                .frame(height: restingTrackHeight)
                .frame(maxWidth: .infinity)
        }
    }

    private var sliderTint: Color {
        if let tintOverride {
            return tintOverride
        }
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }

    private var timeLabelColor: Color {
        if let tintOverride {
            return tintOverride
        }
        return Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    /// Whether the reported duration is one a track could actually have.
    ///
    /// Senders do not always report a usable one — a live stream has none to
    /// give, and some hand back a sentinel or an epoch timestamp instead. The
    /// remaining-time label subtracts the position from it and formats the
    /// result as hours, so an epoch came out on screen as `-1732919508:00:54`.
    /// A day is well past any track and well short of any of those.
    private var hasUsableDuration: Bool {
        duration.isFinite && duration > 0 && duration <= 24 * 60 * 60
    }

    /// Shown in place of a time there is no sensible value for, rather than a
    /// formatted impossibility.
    private static let unknownTime = "--:--"

    private var trailingTimeText: String {
        guard hasUsableDuration else { return Self.unknownTime }

        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            // A position that is not a position cannot be subtracted from
            // anything, and a negative one would inflate what is left rather
            // than reduce it.
            guard sliderValue.isFinite, sliderValue >= 0 else { return Self.unknownTime }

            let remaining = timeString(from: max(duration - sliderValue, 0))
            // The minus belongs to a time, not to the absence of one: prefixing
            // it unconditionally turned --:-- into ---:--.
            return remaining == Self.unknownTime ? remaining : "-" + remaining
        }
    }

    private var inlineLabelFont: Font {
        .system(size: 11, weight: .medium, design: .default).monospacedDigit()
    }

    private var sliderFrameHeight: CGFloat {
        max(restingTrackHeight, draggingTrackHeight)
    }

    func timeString(from seconds: Double) -> String {
        // Int(_:) traps on a value too large to represent, and NaN has no
        // meaning here either; neither belongs on screen as a time.
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else {
            return Self.unknownTime
        }

        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

}


struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// See `MusicSliderView.desaturatesWhenIdle`.
    var desaturatesWhenIdle: Bool = false
    
    @State private var isHovering: Bool = false
    @Default(.enableRealTimeWaveform) var enableRealTimeWaveform
    @Default(.enableWaveformScrubber) var enableWaveformScrubber

    private var isEngaged: Bool { dragging || isHovering }

    private var trackSaturation: Double {
        desaturatesWhenIdle && !isEngaged ? 0 : 1
    }

    private var trackOpacity: Double {
        guard desaturatesWhenIdle else { return 1 }
        return isEngaged ? 1 : 0.82
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackHeight = CGFloat(dragging ? draggingTrackHeight : restingTrackHeight)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width
            
            let showScrubber = isHovering && enableRealTimeWaveform && enableWaveformScrubber

            ZStack(alignment: .bottomLeading) {
                // Background track
                if showScrubber {
                    RealTimeWaveformScrubberView(
                        color: color,
                        secondaryColor: Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.secondaryColor) : nil,
                        progress: progress,
                        minHeight: trackHeight
                    )
                    .frame(height: trackHeight * 3.5)
                    .offset(y: trackHeight * 0.2)
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                }

                // Filled track
                if !showScrubber {
                    Rectangle()
                        .fill(color)
                        .frame(width: filledTrackWidth, height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                }
            }
            // The track swells from its middle, so it grows into the space
            // above and below equally instead of climbing off the baseline --
            // which is also what leaves it level with the times beside it.
            // The waveform scrubber is the exception: it is 3.5x the track and
            // is drawn to rise out of the bar, so it stays bottom-anchored.
            .frame(
                height: max(restingTrackHeight, draggingTrackHeight),
                alignment: showScrubber ? .bottom : .center
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .saturation(trackSaturation)
            // Kept well above the volume bar's resting brightness: a seek bar
            // that fades as far as that one reads as disabled rather than idle.
            .opacity(trackOpacity)
            .animation(.easeOut(duration: 0.2), value: trackSaturation)
            .animation(.easeOut(duration: 0.2), value: trackOpacity)
            .animation(.bouncy.speed(1.4), value: dragging)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }
}

private struct MediaOutputPickerButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var popoverToken = UUID()
    @EnvironmentObject private var vm: DynamicIslandViewModel

    var body: some View {
        HoverButton(icon: buttonIcon, iconColor: .white, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                routeManager.refreshDevices()
            }
        }
        .accessibilityLabel("Media output")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            MediaOutputSelectorPopover(
                routeManager: routeManager,
                volumeModel: volumeModel,
                onHoverChanged: { _ in }
            ) {
                isPopoverPresented = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            routeManager.refreshDevices()
        }
        .onChange(of: isPopoverPresented) { _, _ in
            updatePopoverActivity()
        }
        .onDisappear {
            vm.setMediaOutputPopoverActive(false, token: popoverToken)
        }
    }

    private var buttonIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    /// Reports whether this picker's popover is open, so the notch knows not to
    /// auto-close while it is.
    ///
    /// Keyed by a token unique to this presenter: several pickers can exist at
    /// once and the notch has to stay open while *any* of them is showing, so
    /// the view model tracks a set of open popovers rather than one flag that
    /// the second picker to close would clear on behalf of the first.
    private func updatePopoverActivity() {
        // Presentation alone, deliberately. Also requiring the pointer to be over
        // the popover raced the notch's own hover tracking: the popover is a
        // separate window, so moving into it reads as leaving the notch, and any
        // moment before the popover reported the pointer let the auto-close timer
        // shut the notch and take the popover with it. This is what the stats,
        // timer and clipboard popovers already do.
        vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
    }
}

private struct AirPlayPickerButton: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @State private var isPopoverPresented = false
    @State private var popoverToken = UUID()
    @EnvironmentObject private var vm: DynamicIslandViewModel

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    var body: some View {
        HoverButton(icon: "airplayaudio", iconColor: .white, scale: .medium) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .accessibilityLabel("AirPlay")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { _ in }
            ) {
                isPopoverPresented = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            if isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onChange(of: isPopoverPresented) { _, _ in
            updatePopoverActivity()
        }
        .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
            if newBundle == "com.apple.Music" {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onDisappear {
            vm.setMediaOutputPopoverActive(false, token: popoverToken)
        }
    }

    /// Reports whether this picker's popover is open, so the notch knows not to
    /// auto-close while it is.
    ///
    /// Keyed by a token unique to this presenter: several pickers can exist at
    /// once and the notch has to stay open while *any* of them is showing, so
    /// the view model tracks a set of open popovers rather than one flag that
    /// the second picker to close would clear on behalf of the first.
    private func updatePopoverActivity() {
        // Presentation alone, deliberately. Also requiring the pointer to be over
        // the popover raced the notch's own hover tracking: the popover is a
        // separate window, so moving into it reads as leaving the notch, and any
        // moment before the popover reported the pointer let the auto-close timer
        // shut the notch and take the popover with it. This is what the stats,
        // timer and clipboard popovers already do.
        vm.setMediaOutputPopoverActive(isPopoverPresented, token: popoverToken)
    }
}

struct MediaOutputSelectorPopover: View {
    @ObservedObject var routeManager: AudioRouteManager
    @ObservedObject var volumeModel: MediaOutputVolumeViewModel
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    volumeModel.toggleMute()
                } label: {
                    // Half the chip, which is about where Apple puts a glyph
                    // inside a circular one. At 18pt the speaker's waves ran
                    // right up against the edge of the circle.
                    Image(systemName: volumeIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.18))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(volumeModel.level) },
                        set: { newValue in
                            volumeModel.setVolume(Float(newValue))
                        }
                    ),
                    in: 0 ... 1
                )
                .tint(.accentColor)
            }

            HStack {
                Text("Output volume")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(volumePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output devices")
                .font(.caption)
                .foregroundColor(.secondary)

            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                routeManager.select(device: device)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(device.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(device.id == routeManager.activeDeviceID ? Color.primary.opacity(0.12) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
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
}

struct AirPlaySelectorPopover: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay")
                .font(.caption)
                .foregroundColor(.secondary)

            if airPlayManager.devices.isEmpty {
                Text("No AirPlay devices found")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.name)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(device.isSelected ? Color.primary.opacity(0.12) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }
}

/// Local @State slider decoupled from the manager's @Published state.
/// This prevents SwiftUI from resetting the slider position when other
/// published properties on the manager change during a drag.
struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.accentColor)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float
    @Published var isMuted: Bool

    private let controller: SystemVolumeController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: SystemVolumeController = .shared) {
        self.controller = controller
        controller.start()
        level = controller.currentVolume
        isMuted = controller.isMuted

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["value"] as? Float,
                      let muted = notification.userInfo?["muted"] as? Bool else { return }
                self.level = value
                self.isMuted = muted
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromController()
            }
            .store(in: &cancellables)
    }

    /// How long the volume HUD stays suppressed after a change made from one of
    /// our own controls. Refreshed on every change, so a drag holds it off until
    /// shortly after the last movement.
    private static let ownControlHUDSuppression: TimeInterval = 1.5

    func setVolume(_ value: Float) {
        // The user is already looking at a volume control. Letting the change
        // raise the notch's volume HUD puts a second slider on screen and swaps
        // out the content this one is anchored to, tearing the popover down
        // mid-drag -- which is why the slider could not be dragged at all.
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: Self.ownControlHUDSuppression)
        isMuted.toggle()
        controller.toggleMute()
    }

    private func syncFromController() {
        level = controller.currentVolume
        isMuted = controller.isMuted
    }
}

#Preview {
    NotchHomeView(
        albumArtNamespace: Namespace().wrappedValue
    )
    .environmentObject(DynamicIslandViewModel())
}
