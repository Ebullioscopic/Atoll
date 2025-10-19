//
//  MinimalisticMusicPlayerView.swift
//  DynamicIsland
//
//  Created for minimalistic UI mode - Open state music player
//

import SwiftUI
import Defaults

struct MinimalisticMusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            // Header area with album art (matching DynamicIslandHeader height of 24pt)
            HStack(alignment: .bottom, spacing: 10) {
                MinimalisticAlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                    .frame(width: 50, height: 50)
                
                // Song info aligned to bottom of album art
                VStack(alignment: .leading, spacing: 1) {
                    Text(MusicManager.shared.songTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(MusicManager.shared.artistName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: MusicManager.shared.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Visualizer aligned to bottom
                if useMusicVisualizer {
                    visualizer
                        .padding(.bottom, 2)
                }
            }
            .frame(height: 50) // Fixed height to accommodate album art
            
            // Compact progress bar
            progressBar
                .padding(.top, 4)
            
            // Compact playback controls
            playbackControls
                .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 0)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Visualizer
    
    @Default(.useMusicVisualizer) var useMusicVisualizer
    
    private var visualizer: some View {
        Rectangle()
            .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.avgColor).gradient : Color.gray.gradient)
            .mask {
                AudioSpectrumView(isPlaying: .constant(MusicManager.shared.isPlaying))
                    .frame(width: 20, height: 16)
            }
            .frame(width: 20, height: 16)
            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
    }
    
    // MARK: - Progress Bar (Full Width)
    
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    
    private var progressBar: some View {
        HStack(spacing: 8) {
            // Elapsed time - left
            Text(formatTime(dragging ? sliderValue : musicManager.elapsedTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 42, alignment: .leading)
            
            // Progress bar
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
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
                                dragging = true
                                let newValue = min(max(0, Double(value.location.x / geometry.size.width) * musicManager.songDuration), musicManager.songDuration)
                                sliderValue = newValue
                                lastDragged = Date()
                            }
                            .onEnded { _ in
                                musicManager.seek(to: sliderValue)
                                dragging = false
                            }
                    )
                }
            }
            .frame(height: 6)
            
            // Time remaining - right
            Text("-\(formatTime(musicManager.songDuration - (dragging ? sliderValue : musicManager.elapsedTime)))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 48, alignment: .trailing)
        }
        .onAppear {
            sliderValue = musicManager.elapsedTime
        }
    }
    
    private func currentSliderValue(_ date: Date) -> Double {
        if dragging {
            return sliderValue
        }
        
        // Update slider value based on playback
        if musicManager.isPlaying {
            let timeSinceLastUpdate = date.timeIntervalSince(musicManager.lastUpdated)
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
    
    // MARK: - Playback Controls (Larger)
    
    private var playbackControls: some View {
        HStack(spacing: 20) {
            if Defaults[.showShuffleAndRepeat] {
                controlButton(icon: "shuffle", isActive: musicManager.isShuffled) {
                    Task { await musicManager.toggleShuffle() }
                }
            }
            
            controlButton(icon: "backward.fill", size: 18) {
                Task { await musicManager.previousTrack() }
            }
            
            playPauseButton
            
            controlButton(icon: "forward.fill", size: 18) {
                Task { await musicManager.nextTrack() }
            }
            
            if Defaults[.showShuffleAndRepeat] {
                controlButton(icon: repeatIcon, isActive: musicManager.repeatMode != .off) {
                    Task { await musicManager.toggleRepeat() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
    
    private var playPauseButton: some View {
        Button(action: {
            Task { await musicManager.togglePlay() }
        }) {
            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func controlButton(icon: String, size: CGFloat = 18, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(isActive ? .red : .white.opacity(0.8))
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
}

// MARK: - Minimalistic Album Art

struct MinimalisticAlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID

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
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 35)
            .opacity(min(0.6, 1 - max(musicManager.albumArt.getBrightness(), 0.3)))
    }
    
    private var albumArtButton: some View {
        Button {
            musicManager.openMusicApp()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: musicManager.isFlipping)
                )
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(musicManager.isPlaying ? 1 : 0.4)
        .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
    }
}
