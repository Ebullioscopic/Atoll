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

/// Custom OSD panel that mimics macOS native OSD appearance
/// Supports volume, brightness, and keyboard backlight displays
struct CustomOSDView: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Environment(\.colorScheme) var colorScheme
    
    private let iconSize: CGFloat = 56
    private let progressBarHeight: CGFloat = 6
    private let spacing: CGFloat = 20
    private let segmentCount: Int = 16
    
    var body: some View {
        VStack(spacing: spacing) {
            // Icon
            ZStack {
                Image(systemName: symbolName)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 80, height: 60, alignment: .center) // Fixed container for icon
            
            // Progress/Value Indicator
            progressView
                .frame(width: 140)
                .padding(.top, 4) // Lower the bar slightly
        }
        .frame(width: 200, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.1)) // Subtle backing for shadow source
                .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 8)
        )
        .background(
            backgroundView
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    // MARK: - Symbol Logic
    
    private var symbolName: String {
        if !icon.isEmpty {
            return icon
        }
        
        switch type {
        case .volume:
            if value < 0.01 {
                return "speaker.slash.fill"
            } else if value < 0.33 {
                return "speaker.fill"
            } else if value < 0.66 {
                return "speaker.wave.1.fill"
            } else {
                return "speaker.wave.3.fill"
            }
            
        case .brightness:
            return "sun.max.fill"
            
        case .backlight:
            return value >= 0.5 ? "light.max" : "light.min"
            
        default:
            return "questionmark"
        }
    }
    
    private var iconColor: Color {
        switch osdIconColorStyle {
        case .white:
            return .white
        case .whiteTransparent:
            return .white.opacity(0.85)
        case .lightGray:
            return Color(white: 0.85)
        case .darkGray:
            return Color(white: 0.3)
        case .black:
            return .black
        case .blackTransparent:
            return .black.opacity(0.85)
        case .auto:
            return colorScheme == .dark ? .white : .black
        case .autoTransparent:
            return colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.85)
        }
    }
    
    private var textColor: Color {
        switch osdIconColorStyle {
        case .white, .whiteTransparent, .lightGray:
            return .white
        case .darkGray, .black, .blackTransparent:
            return .black
        case .auto, .autoTransparent:
            return colorScheme == .dark ? .white : .black
        }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < Int(value * CGFloat(segmentCount)) ? iconColor : inactiveSegmentColor)
                    .frame(width: 6, height: progressBarHeight)
            }
        }
    }
    
    private var inactiveSegmentColor: Color {
        switch osdIconColorStyle {
        case .white, .whiteTransparent, .lightGray:
            return Color.white.opacity(0.25)
        case .darkGray, .black, .blackTransparent:
            return Color.black.opacity(0.25)
        case .auto, .autoTransparent:
            return colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.25)
        }
    }
    
    // MARK: - Background
    
    @ViewBuilder
    private var backgroundView: some View {
        switch osdMaterial {
        case .frosted:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        case .liquid:
            if #available(macOS 26.0, *) {
                if osdLiquidGlassCustomizationMode == .customLiquid {
                    LiquidGlassBackground(
                        variant: osdLiquidGlassVariant,
                        cornerRadius: 18
                    ) {
                        Color.white.opacity(0.04)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        #if compiler(>=6.2)
                        .glassEffect(
                            .clear.interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                        #else
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
                        #endif
                }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        case .solidDark:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
        case .solidLight:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.85))
        case .solidAuto:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.85))
        }
    }
}

// MARK: - OSD Material Enum

enum OSDMaterial: String, CaseIterable, Defaults.Serializable {
    case frosted = "Frosted Glass"
    case liquid = "Liquid Glass"
    case solidDark = "Solid Dark"
    case solidLight = "Solid Light"
    case solidAuto = "Solid Auto"
}

// MARK: - OSD Icon Color Style Enum

enum OSDIconColorStyle: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case whiteTransparent = "White (Transparent)"
    case lightGray = "Light Gray"
    case darkGray = "Dark Gray"
    case black = "Black"
    case blackTransparent = "Black (Transparent)"
    case auto = "Auto"
    case autoTransparent = "Auto (Transparent)"
}

#endif
