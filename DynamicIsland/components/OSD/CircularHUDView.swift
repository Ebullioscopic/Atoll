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

#if os(macOS)
import SwiftUI
import Defaults
import CoreAudio

struct CircularHUDView: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    
    @Default(.circularHUDShowValue) var showValue
    @Default(.circularHUDSize) var size
    @Default(.circularHUDStrokeWidth) var strokeWidth
    @Default(.circularHUDUseAccentColor) var useAccentColor
    
    @Environment(\.colorScheme) var colorScheme
    
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolume
    @Default(.useSmoothColorGradient) var useSmoothGradient
    
    var body: some View {
        ZStack {
            // Background circle (SOLO OPAQUE - No transparency)
            Circle()
                .fill(Color(white: 0.1))
                .overlay {
                    Circle()
                        .stroke(Color(white: 0.2), lineWidth: 1)
                }
            
            // 1. Static Background Track (Empty binario)
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color(white: 0.15), style: StrokeStyle(lineWidth: strokeWidth * 1.5, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)
            
            // 2. Animated Progress Arc (Filled part)
            Circle()
                .trim(from: 0.15, to: 0.15 + (0.7 * value))
                .stroke(strokeStyle, style: StrokeStyle(lineWidth: strokeWidth * 1.5, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: size, height: size)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: value)
            
            // 3. The "Ball" Indicator (Oversized White Pallino)
            GeometryReader { _ in
                let radius = size / 2
                let trackWidth = strokeWidth * 1.5
                let startAngle = 144.0
                let currentAngle = startAngle + (252.0 * value)
                
                let x = radius + radius * cos(currentAngle * .pi / 180)
                let y = radius + radius * sin(currentAngle * .pi / 180)
                
                Circle()
                    .fill(.white)
                    .frame(width: trackWidth * 1.45, height: trackWidth * 1.45)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1.2)
                    .position(x: x, y: y)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: value)
            }
            .frame(width: size, height: size)
            
            // Central Icon
            Image(systemName: symbolName)
                .font(.system(size: size * 0.32, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: symbolName)
            
            // Bottom Value Label
            if showValue {
                VStack {
                    Spacer()
                    HUDNumericLabel(
                        value: value,
                        font: .system(size: size * 0.15, weight: .bold, design: .rounded),
                        color: .white.opacity(0.65)
                    )
                    .padding(.bottom, size * 0.03)
                }
            }

        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var strokeStyle: AnyShapeStyle {
        if type == .volume && useColorCodedVolume {
            return ColorCodedProgressBar.shapeStyle(for: value, mode: .volume, smoothGradient: useSmoothGradient)
        }
        
        if useAccentColor {
            return AnyShapeStyle(Color(NSColor.controlAccentColor))
        }
        
        // Default to the approved solid dark gray to match reference when not colored
        return AnyShapeStyle(Color(white: 0.25))
    }
    
    private var symbolName: String {
        if !icon.isEmpty { return icon }
        
        switch type {
        case .volume:
            // Check if headphones/AirPods are connected
            let deviceInfo = getAudioDeviceInfo()
            
            if deviceInfo.isAirPods {
                // Use AirPods icon when AirPods are connected
                if value < 0.01 { return "headphones.slash" } else { return "airpods" }
            } else if deviceInfo.isHeadphones {
                // Use headphone icons when other headphones are connected
                if value < 0.01 { return "headphones.slash" } else { return "headphones" }
            } else {
                // Use speaker icons for built-in speakers
                if value < 0.01 { return "speaker.slash.fill" } else if value < 0.33 { return "speaker.wave.1.fill" } else if value < 0.66 { return "speaker.wave.2.fill" } else { return "speaker.wave.3.fill" }
            }
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "keyboard"
        default:
            return "questionmark"
        }
    }
    
    private struct AudioDeviceInfo {
        let isAirPods: Bool
        let isHeadphones: Bool
    }
    
    private func getAudioDeviceInfo() -> AudioDeviceInfo {
        #if os(macOS)
        // Get default output device
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else {
            return AudioDeviceInfo(isAirPods: false, isHeadphones: false)
        }
        
        // Get device name
        var deviceName: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &deviceName) == noErr else {
            return AudioDeviceInfo(isAirPods: false, isHeadphones: false)
        }
        
        let name = (deviceName as String).lowercased()
        
        // Check for AirPods specifically
        let isAirPods = name.contains("airpod")
        
        // Check for other headphones
        let isHeadphones = name.contains("headphone") ||
                          name.contains("ear") ||
                          name.contains("buds") ||
                          name.contains("beats")
        
        return AudioDeviceInfo(isAirPods: isAirPods, isHeadphones: !isAirPods && isHeadphones)
        #else
        return AudioDeviceInfo(isAirPods: false, isHeadphones: false)
        #endif
    }
}
#endif
