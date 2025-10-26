//
//  InlineHUDs.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

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
    @ObservedObject var bluetoothManager = BluetoothAudioManager.shared
    
    @State private var displayName: String = ""
    
    var body: some View {
        let useCircularIndicator = useCircularBluetoothBatteryIndicator
        let hasBatteryLevel = value > 0

        let baseInfoWidth: CGFloat = {
            if type == .bluetoothAudio {
                return showBluetoothDeviceNameMarquee ? 100 : 52
            }
            return 100
        }()
        let infoWidth = baseInfoWidth - (hoverAnimation ? 0 : 12) + gestureProgress / 2
        let baseTrailingWidth: CGFloat = {
            if type == .bluetoothAudio {
                if !hasBatteryLevel {
                    return showBluetoothDeviceNameMarquee ? 100 : 70
                }

                if useCircularIndicator {
                    return showBluetoothBatteryPercentageText ? 100 : 70
                } else {
                    return showBluetoothBatteryPercentageText ? 112 : 82
                }
            }
            return 100
        }()
        let trailingWidth = baseTrailingWidth - (hoverAnimation ? 0 : 12) + gestureProgress / 2

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
                            Image(systemName: BrightnessSymbol(value))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .backlight:
                            Image(systemName: "keyboard")
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
                            Image(systemName: icon.isEmpty ? "bluetooth" : icon)
                                .symbolRenderingMode(.hierarchical)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
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
                } else {
                    Text(Type2Name(type))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: infoWidth, height: vm.notchSize.height - (hoverAnimation ? 0 : 12), alignment: .leading)
            
            Rectangle()
                .fill(.black)
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
                } else if (type == .bluetoothAudio) {
                    if hasBatteryLevel {
                        HStack(spacing: useCircularIndicator ? 8 : 6) {
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
            .padding(.trailing, 4)
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
                    .stroke(Color.white.opacity(0.18), lineWidth: 2.6)

                Circle()
                    .trim(from: 0, to: max(clampedValue, 0.015))
                    .rotation(.degrees(-90))
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            }
            .frame(width: 22, height: 22)
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
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return "Brightness"
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            case .bluetoothAudio:
                return BluetoothAudioManager.shared.lastConnectedDevice?.name ?? "Bluetooth"
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
