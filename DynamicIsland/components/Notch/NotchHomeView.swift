//
//  NotchHomeView.swift
//  DynamicIsland
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    let albumArtNamespace: Namespace.ID
    let showShuffleAndRepeat: Bool

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView(showShuffleAndRepeat: showShuffleAndRepeat).drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
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
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
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
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: Defaults[.cornerRadiusScaling]
                    ? MusicPlayerImageSizes.cornerRadiusInset.opened
                    : MusicPlayerImageSizes.cornerRadiusInset.closed)
        )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity).animation(.bouncy.delay(0.3)))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    let showShuffleAndRepeat: Bool
    @Default(.showMediaOutputControl) private var showMediaOutputControl

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            playbackControls
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText($musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white, frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor)
                    .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
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
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            if showShuffleAndRepeat {
                HoverButton(
                    icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .white,
                    scale: .medium
                ) {
                    MusicManager.shared.toggleShuffle()
                }
            }
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
            if showShuffleAndRepeat {
                if showMediaOutputControl {
                    MediaOutputPickerButton()
                } else {
                    HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                        MusicManager.shared.toggleRepeat()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
            return .red
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    let albumArtNamespace: Namespace.ID
    
    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 20) {
            if Defaults[.enableMinimalisticUI] {
                // Minimalistic mode: Only show compact music player
                MinimalisticMusicPlayerView(albumArtNamespace: albumArtNamespace)
            } else {
                // Normal mode: Show full music player with optional calendar and webcam
                MusicPlayerView(albumArtNamespace: albumArtNamespace, showShuffleAndRepeat: Defaults[.showShuffleAndRepeat])
                
                if Defaults[.showCalendar] {
                    CalendarView()
                        .onHover { isHovering in
                            vm.isHoveringCalendar = isHovering
                        }
                        .environmentObject(vm)
                }
                
                if Defaults[.showMirror],
                   webcamManager.cameraAvailable,
                   vm.notchState == .open {
                    CameraPreviewView(webcamManager: webcamManager)
                        .scaledToFit()
                        .opacity(vm.notchState == .closed ? 0 : 1)
                        .blur(radius: vm.notchState == .closed ? 20 : 0)
                }
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
            .combined(with: .move(edge: .top)))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
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
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0 ... duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt ? Color(
                    nsColor: color
                ).ensureMinimumBrightness(factor: 0.8) : Defaults[.sliderColor] == SliderColorEnum.accent ? .accentColor : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)
            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: color)
                .ensureMinimumBrightness(factor: 0.6) : .gray)
            .font(.caption)
        }
        .onChange(of: currentDate) { newDate in
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: newDate)
        }
    }

    func timeString(from seconds: Double) -> String {
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                // Filled track
                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
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
            .animation(.bouncy.speed(1.4), value: dragging)
        }
    }
}

private struct MediaOutputPickerButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var isHoveringPopover = false
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
                onHoverChanged: { hovering in
                    isHoveringPopover = hovering
                    updatePopoverActivity()
                }
            ) {
                isPopoverPresented = false
                isHoveringPopover = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            routeManager.refreshDevices()
        }
        .onChange(of: isPopoverPresented) { _, presented in
            if !presented {
                isHoveringPopover = false
            }
            updatePopoverActivity()
        }
        .onDisappear {
            vm.isMediaOutputPopoverActive = false
        }
    }

    private var buttonIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private func updatePopoverActivity() {
        vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
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
                    Image(systemName: volumeIconName)
                        .font(.system(size: 18, weight: .semibold))
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
                .frame(maxHeight: 180)
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

    func setVolume(_ value: Float) {
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
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
