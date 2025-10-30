//
//  LockScreenMusicPanel.swift
//  DynamicIsland
//
//  Created for lock screen music panel with liquid glass effect
//

import SwiftUI
import Defaults

struct LockScreenMusicPanel: View {
    static let collapsedSize = CGSize(width: 420, height: 180)
    static let expandedSize = CGSize(width: 720, height: 340) // Kept for compatibility; window will go fullscreen when expanded

    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var isActive = true
    @State private var isExpanded = false
    @State private var collapseWorkItem: DispatchWorkItem?
    @Default(.lockScreenGlassStyle) var lockScreenGlassStyle
    @Default(.lockScreenShowAppIcon) var showAppIcon
    @Default(.lockScreenPanelShowsBorder) var showPanelBorder
    @Default(.lockScreenPanelUsesBlur) var enableBlur
    
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private let collapsedAlbumArtCornerRadius: CGFloat = 16
    private let expandedAlbumArtCornerRadius: CGFloat = 20
    private let expandedContentSpacing: CGFloat = 40
    private let collapseTimeout: TimeInterval = 5

    private var currentSize: CGSize {
        isExpanded ? Self.expandedSize : Self.collapsedSize
    }

    private var panelCornerRadius: CGFloat {
        isExpanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
    }

    private var usesLiquidGlass: Bool {
        if #available(macOS 26.0, *) {
            return lockScreenGlassStyle == .liquid
        }
        return false
    }
    
    var body: some View {
        if isActive {
            panelContent
        } else {
            Color.clear
                .frame(width: Self.collapsedSize.width, height: Self.collapsedSize.height)
        }
    }
    
    private var panelContent: some View {
        panelCore
            .frame(
                width: isExpanded ? nil : currentSize.width,
                height: isExpanded ? nil : currentSize.height
            )
            .frame(maxWidth: isExpanded ? .infinity : nil, maxHeight: isExpanded ? .infinity : nil)
            .animation(.spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.18), value: isExpanded)
            .onAppear {
                sliderValue = musicManager.elapsedTime
                isActive = true
                logPanelAppearance()
                LockScreenPanelManager.shared.updatePanelSize(expanded: false, animated: false)
            }
            .onDisappear {
                isActive = false
                cancelCollapseTimer()
            }
            .onChange(of: isExpanded) { _, expanded in
                LockScreenPanelManager.shared.updatePanelSize(expanded: expanded)
            }
    }

    @ViewBuilder
    private var panelCore: some View {
        Group {
            if isExpanded {
                fullscreenExpandedView
            } else {
                collapsedLayout
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(width: currentSize.width, height: currentSize.height, alignment: .topLeading)
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                    .overlay {
                        if showPanelBorder {
                            RoundedRectangle(cornerRadius: panelCornerRadius)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1.4)
                        }
                    }
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                    .contentShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            }
        }
    }

    // MARK: - Fullscreen Expanded View
    
    private var fullscreenExpandedView: some View {
        ZStack {
            // Blurred background
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 0.6)
                .overlay(Color.black.opacity(0.4))
                .ignoresSafeArea(.all)
            
            // Content overlay
            HStack(alignment: .center, spacing: 60) {
                // Clickable album art (left side) - not blurred
                Button(action: toggleExpanded) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 400, height: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 15)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Info and controls (right side)
                VStack(alignment: .leading, spacing: 30) {
                    // Song info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    // Progress bar
                    progressBar
                        .frame(maxWidth: 500)
                    
                    // Playback controls
                    fullscreenPlaybackControls
                        .padding(.top, 10)
                }
                .frame(maxWidth: 500)
            }
            .padding(.horizontal, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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


    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            albumArtButton(size: 60, cornerRadius: collapsedAlbumArtCornerRadius)

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.songTitle.isEmpty ? "No Music Playing" : musicManager.songTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                    .lineLimit(1)
            }

            Spacer()

            visualizer(width: 20, height: 16)
        }
        .frame(height: 60)
    }


    private func albumArtButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Button(action: toggleExpanded) {
            ZStack(alignment: .bottomTrailing) {
                albumArtImage(size: size, cornerRadius: cornerRadius)
                if showAppIcon, let icon = lockScreenAppIcon {
                    icon
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: appIconSize, height: appIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: appIconCornerRadius, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 4)
                        .offset(x: appIconOffset, y: appIconOffset)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .albumArtFlip(angle: musicManager.flipAngle)
            .frame(width: size, height: size)
            .background(albumArtBackground(cornerRadius: cornerRadius))
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.2), value: musicManager.isPlaying)
    }

    @ViewBuilder
    private func visualizer(width: CGFloat, height: CGFloat) -> some View {
        if Defaults[.useMusicVisualizer] {
            Rectangle()
                .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                .mask {
                    AudioSpectrumView(isPlaying: .constant(musicManager.isPlaying))
                        .frame(width: width, height: height)
                }
                .frame(width: width, height: height)
        }
    }

    private func toggleExpanded() {
        let newState = !isExpanded
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
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

    private func registerInteraction() {
        cancelCollapseTimer()
        // In fullscreen mode we do not auto-collapse; exit is by clicking the small album art
        guard isExpanded == false else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                isExpanded = false
            }
            logPanelAppearance(event: "⏱️ Auto-collapsed")
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseTimeout, execute: workItem)
    }

    private func cancelCollapseTimer() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            let currentElapsed = currentSliderValue(timeline.date)
            
            HStack(spacing: 8) {
                // Elapsed time
                Text(formatTime(dragging ? sliderValue : currentElapsed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 42, alignment: .leading)
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
                        // Filled portion
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sliderColor)
                            .frame(width: max(0, geometry.size.width * (currentSliderValue(timeline.date) / max(musicManager.songDuration, 1))), height: 6)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                registerInteraction()
                                dragging = true
                                let newValue = min(max(0, Double(value.location.x / geometry.size.width) * musicManager.songDuration), musicManager.songDuration)
                                sliderValue = newValue
                            }
                            .onEnded { _ in
                                registerInteraction()
                                musicManager.seek(to: sliderValue)
                                dragging = false
                            }
                    )
                }
                .frame(height: 6)
                
                // Time remaining
                Text("-\(formatTime(musicManager.songDuration - (dragging ? sliderValue : currentElapsed)))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
    }
    
    private func currentSliderValue(_ date: Date) -> Double {
        if dragging {
            return sliderValue
        }
        
        if musicManager.isPlaying {
            let timeSinceLastUpdate = date.timeIntervalSince(musicManager.timestampDate)
            let estimatedElapsed = musicManager.elapsedTime + (timeSinceLastUpdate * musicManager.playbackRate)
            return min(estimatedElapsed, musicManager.songDuration)
        }
        
        return musicManager.elapsedTime
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
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Playback Controls
    
    private var fullscreenPlaybackControls: some View {
        HStack(spacing: 32) {
            controlButton(icon: "shuffle", size: 24, isActive: musicManager.isShuffled) {
                musicManager.toggleShuffle()
            }
            
            controlButton(icon: "backward.fill", size: 28) {
                musicManager.previousTrack()
            }
            
            // Large play/pause button
            Button(action: {
                registerInteraction()
                musicManager.togglePlay()
            }) {
                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 90, height: 90)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            
            controlButton(icon: "forward.fill", size: 28) {
                musicManager.nextTrack()
            }
            
            controlButton(icon: repeatIcon, size: 24, isActive: musicManager.repeatMode != .off) {
                musicManager.toggleRepeat()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func playbackControls(alignment: Alignment) -> some View {
        let spacing: CGFloat = isExpanded ? 24 : 20

        return HStack(spacing: spacing) {
            // Always show shuffle on lock screen
            controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                musicManager.toggleShuffle()
            }
            
            controlButton(icon: "backward.fill", size: 18) {
                musicManager.previousTrack()
            }
            
            playPauseButton
            
            controlButton(icon: "forward.fill", size: 18) {
                musicManager.nextTrack()
            }
            
            // Always show repeat on lock screen
            controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                musicManager.toggleRepeat()
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.top, isExpanded ? 6 : 2)
    }
    
    private var playPauseButton: some View {
        let frameSize: CGFloat = isExpanded ? 72 : 48
        let symbolSize: CGFloat = isExpanded ? 30 : 24

        return Button(action: {
            registerInteraction()
            musicManager.togglePlay()
        }) {
            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func controlButton(icon: String, size: CGFloat = 18, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        let frameSize: CGFloat = isExpanded ? 56 : 32
        let iconSize: CGFloat = isExpanded ? max(size, 24) : size

        return Button(action: {
            registerInteraction()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(isActive ? .red : .white.opacity(0.8))
                .frame(width: frameSize, height: frameSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if enableBlur {
            if usesLiquidGlass {
                liquidPanelBackground
            } else {
                frostedPanelBackground
            }
        } else {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .fill(Color.black.opacity(0.45))
        }
    }

    @ViewBuilder
    private var liquidPanelBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: panelCornerRadius)
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(0.12))
                        .interactive(),
                    in: .rect(cornerRadius: panelCornerRadius)
                )
        }
    }

    private var frostedPanelBackground: some View {
        RoundedRectangle(cornerRadius: panelCornerRadius)
            .fill(.ultraThinMaterial)
    }

    private func albumArtImage(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func albumArtBackground(cornerRadius: CGFloat) -> some View {
        if enableBlur {
            if usesLiquidGlass {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .glassEffect(
                            .regular
                                .tint(Color.white.opacity(0.16))
                                .interactive(),
                            in: .rect(cornerRadius: cornerRadius)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            }
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
        isExpanded ? 18 : 10
    }

    private var appIconOffset: CGFloat {
        isExpanded ? 18 : 12
    }

    private func logPanelAppearance(event: String = "✅ View appeared") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let styleDescriptor = usesLiquidGlass ? "Liquid Glass" : "Frosted"
        print("[\(formatter.string(from: Date()))] LockScreenMusicPanel: \(event) – \(styleDescriptor)")
    }
}
