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

import SwiftUI
import AppKit
import AVFoundation
import Defaults

// MARK: - Inline HUD looping .mov icon

private final class LoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        self.player = AVQueuePlayer()
        self.player.isMuted = true
        self.player.actionAtItemEnd = .none
        self.looper = AVPlayerLooper(player: self.player, templateItem: item)
        self.player.play()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

private struct LoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds

        view.layer?.addSublayer(layer)

        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op; the animation loops via AVPlayerLooper.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: LoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = LoopingPlayerController(url: url)
            layer.player = controller?.player
        }
    }
}

struct InlineHUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    
    @Default(.useColorCodedBatteryDisplay) var useColorCodedBatteryDisplay
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolumeDisplay
    @Default(.useSmoothColorGradient) var useSmoothColorGradient
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.showProgressPercentages) var showProgressPercentages
    @Default(.useCircularBluetoothBatteryIndicator) var useCircularBluetoothBatteryIndicator
    @Default(.showBluetoothBatteryPercentageText) var showBluetoothBatteryPercentageText
    @Default(.showBluetoothDeviceNameMarquee) var showBluetoothDeviceNameMarquee
    @Default(.useBluetoothHUD3DIcon) var useBluetoothHUD3DIcon
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @ObservedObject var bluetoothManager = BluetoothAudioManager.shared
    
    @State private var displayName: String = ""
    
    var body: some View {
        let useCircularIndicator = useCircularBluetoothBatteryIndicator
        let hasBatteryLevel = value > 0
        let capsLockAccentColor = capsLockTintMode.color

        // Widths stay constant whether hovered or not so HUD text/icons do
        // not slide toward the notch edges when the user moves over it.
        // Mini BT marquee widths are reduced to keep both wings inside the
        // minimalistic open notch (420pt) on wider hardware notches.
        let baseInfoWidth: CGFloat = {
            if type == .bluetoothAudio {
                if showBluetoothDeviceNameMarquee {
                    return enableMinimalisticUI ? 96 : 132
                }
                return enableMinimalisticUI ? 56 : 64
            }

            if type == .capsLock && !showCapsLockLabel {
                return enableMinimalisticUI ? 48 : 56
            }

            return 92
        }()

        let infoWidth: CGFloat = {
            let width = baseInfoWidth + gestureProgress / 2
            let minimum: CGFloat = {
                if type == .bluetoothAudio {
                    if showBluetoothDeviceNameMarquee {
                        return enableMinimalisticUI ? 84 : 112
                    }
                    return enableMinimalisticUI ? 48 : 60
                }

                if type == .capsLock && !showCapsLockLabel {
                    return enableMinimalisticUI ? 36 : 44
                }

                return 88
            }()
            return max(width, minimum)
        }()

        let baseTrailingWidth: CGFloat = {
            if type == .bluetoothAudio {
                if !hasBatteryLevel {
                    return showBluetoothDeviceNameMarquee ? (enableMinimalisticUI ? 88 : 110) : (enableMinimalisticUI ? 66 : 80)
                }

                if useCircularIndicator {
                    return showBluetoothBatteryPercentageText ? (enableMinimalisticUI ? 92 : 112) : (enableMinimalisticUI ? 64 : 76)
                }

                return showBluetoothBatteryPercentageText ? (enableMinimalisticUI ? 100 : 128) : (enableMinimalisticUI ? 84 : 100)
            }

            if type == .capsLock {
                if showCapsLockLabel {
                    return enableMinimalisticUI ? 76 : 88
                }
                return 0
            }

            return 92
        }()

        let trailingWidth: CGFloat = {
            let width = baseTrailingWidth + gestureProgress / 2
            let minimum: CGFloat = {
                if type == .bluetoothAudio {
                    if !hasBatteryLevel {
                        return showBluetoothDeviceNameMarquee ? (enableMinimalisticUI ? 80 : 102) : (enableMinimalisticUI ? 56 : 80)
                    }

                    if useCircularIndicator {
                        return showBluetoothBatteryPercentageText ? (enableMinimalisticUI ? 80 : 102) : (enableMinimalisticUI ? 48 : 64)
                    }

                    return showBluetoothBatteryPercentageText ? (enableMinimalisticUI ? 88 : 112) : (enableMinimalisticUI ? 64 : 82)
                }

                if type == .capsLock {
                    return showCapsLockLabel ? (enableMinimalisticUI ? 60 : 72) : 0
                }

                return 90
            }()
            return max(width, minimum)
        }()

        return HStack {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                // Show headphone icon if Bluetooth audio is connected, otherwise speaker
                                let baseIcon = bluetoothManager.isBluetoothAudioConnected ? "headphones" : SpeakerSymbol(value)
                                Image(systemName: baseIcon)
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Image(systemName: !icon.isEmpty ? icon : BrightnessSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .backlight:
                            Image(systemName: BacklightSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .timer:
                            Image(systemName: "timer")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .bluetoothAudio:
                            if useBluetoothHUD3DIcon,
                               let deviceType = bluetoothManager.lastConnectedDevice?.deviceType,
                               let url = Bundle.main.url(forResource: deviceType.inlineHUDAnimationBaseName, withExtension: "mov") {
                                LoopingVideoIcon(url: url, size: CGSize(width: 20, height: 20))
                                    .frame(width: 20, height: 20, alignment: .center)
                            } else {
                                Image(systemName: icon.isEmpty ? "dot.radiowaves.left.and.right" : icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                            }
                        case .capsLock:
                            Image(systemName: "capslock.fill")
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                                .foregroundStyle(capsLockAccentColor)
                        default:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                // Use marquee text for device names to handle long names
                if type == .bluetoothAudio {
                    if showBluetoothDeviceNameMarquee {
                        MarqueeText(
                            $displayName,
                            font: .system(size: 13, weight: .medium),
                            nsFont: .body,
                            textColor: .white,
                            minDuration: 0.2,
                            frameWidth: infoWidth
                        )
                    }
                } else if type != .capsLock {
                    Text(Type2Name(type))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: infoWidth, height: vm.notchSize.height - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(Defaults[.notchGlassEnabled] ? Color.clear : Color.black)
                .frame(width: vm.closedNotchSize.width - 20)
            
            HStack {
                if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else if (type == .timer) {
                    Text(TimerManager.shared.formattedRemainingTime())
                        .foregroundStyle(TimerManager.shared.timerColor)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else if (type == .capsLock) {
                    if showCapsLockLabel {
                        Text("Caps Lock")
                            .foregroundStyle(capsLockAccentColor)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .contentTransition(.interpolate)
                    }
                } else if (type == .bluetoothAudio) {
                    if hasBatteryLevel {
                        let indicatorSpacing: CGFloat = {
                            if useCircularIndicator {
                                return showBluetoothBatteryPercentageText ? 8 : 2
                            }
                            return showBluetoothBatteryPercentageText ? 6 : 4
                        }()

                        HStack(spacing: indicatorSpacing) {
                            if useCircularIndicator {
                                CircularBatteryIndicator(
                                    value: value,
                                    useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                    smoothGradient: useSmoothColorGradient
                                )
                                .allowsHitTesting(false)
                            } else {
                                LinearBatteryIndicator(
                                    value: value,
                                    useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                    smoothGradient: useSmoothColorGradient
                                )
                                .allowsHitTesting(false)
                            }

                            if showBluetoothBatteryPercentageText {
                                Text("\(Int(value * 100))%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    // Volume and brightness displays
                    Group {
                        if type == .volume {
                            Group {
                                if value.isZero {
                                    Text("muted")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.gray)
                                        .lineLimit(1)
                                        .allowsTightening(true)
                                        .multilineTextAlignment(.trailing)
                                        .contentTransition(.numericText())
                                } else {
                                    HStack(spacing: 6) {
                                        DraggableProgressBar(value: $value, colorMode: .volume)
                                        PercentageLabel(value: value, isVisible: showProgressPercentages)
                                    }
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .animation(.smooth(duration: 0.2), value: value.isZero)
                        } else {
                            HStack(spacing: 6) {
                                DraggableProgressBar(value: $value)
                                PercentageLabel(value: value, isVisible: showProgressPercentages)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.trailing, trailingWidth > 0 ? 4 : 0)
            .frame(width: trailingWidth, height: vm.closedNotchSize.height - (hoverAnimation ? 0 : 12), alignment: .center)
        }
        .frame(height: vm.closedNotchSize.height + (hoverAnimation ? 8 : 0), alignment: .center)
        .onAppear {
            displayName = Type2Name(type)
        }
        .onChange(of: type) { _, _ in
            displayName = Type2Name(type)
        }
        .onChange(of: bluetoothManager.lastConnectedDevice?.name) { _, _ in
            displayName = Type2Name(type)
        }
    }
    
    private struct CircularBatteryIndicator: View {
        let value: CGFloat
        let useColorCoding: Bool
        let smoothGradient: Bool

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var indicatorColor: Color {
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: max(clampedValue, 0.015))
                    .rotation(.degrees(-90))
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .frame(width: 16, height: 16)
            .animation(.smooth(duration: 0.18), value: clampedValue)
        }
    }

    private struct LinearBatteryIndicator: View {
        let value: CGFloat
        let useColorCoding: Bool
        let smoothGradient: Bool

        private let trackWidth: CGFloat = 54
        private let trackHeight: CGFloat = 6

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var fillColor: Color {
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(fillColor)
                    .frame(width: trackWidth * clampedValue, height: trackHeight)
            }
            .frame(width: trackWidth, height: trackHeight)
            .animation(.smooth(duration: 0.18), value: clampedValue)
        }
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }

    func BacklightSymbol(_ value: CGFloat) -> String {
        if value >= 0.5 {
            return "light.max"
        }
        return "light.min"
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return String(localized: "Volume")
            case .brightness:
                return String(localized: "Brightness")
            case .backlight:
                return String(localized: "Backlight")
            case .mic:
                return String(localized: "Mic")
            case .bluetoothAudio:
                return BluetoothAudioManager.shared.lastConnectedDevice?.name ?? "Bluetooth"
            case .capsLock:
                return String(localized: "Caps Lock")
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(DynamicIslandViewModel())
}
