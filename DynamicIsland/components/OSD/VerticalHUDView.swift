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
import Combine

struct BumpEvent: Equatable {
    let direction: Int
    let timestamp: Date
}

class VerticalHUDState: ObservableObject {
    @Published var type: SneakContentType = .volume
    @Published var value: CGFloat = 0
    @Published var icon: String = ""
    @Published var bumpEvent: BumpEvent?
    
    init(type: SneakContentType = .volume, value: CGFloat = 0, icon: String = "") {
        self.type = type
        self.value = value
        self.icon = icon
    }
}

struct VerticalHUDView: View {
    @ObservedObject var state: VerticalHUDState
    
    @Default(.verticalHUDShowValue) var showValue
    @Default(.verticalHUDHeight) var hudHeight
    @Default(.verticalHUDWidth) var hudWidth
    @Default(.verticalHUDUseAccentColor) var useAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant
    @Default(.verticalHUDInteractive) var isInteractive
    
    @Environment(\.colorScheme) var colorScheme
    
    // Interaction State
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var stretchAmount: CGFloat = 0
    @State private var stretchOffset: CGFloat = 0
    
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolume
    @Default(.useSmoothColorGradient) var useSmoothGradient
    
    // Constants
    private let maxStretch: CGFloat = 30 // Reduced max stretch for tighter feel
    
    var body: some View {
        // Full Window Container
        ZStack {
            // The Actual HUD Pill
            ZStack {
                // Background
                verticalBackground
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    }

                // Fill Bar
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(fillStyle)
                            .frame(height: geo.size.height * state.value)
                            // Super Smooth Fill
                            .animation(.interactiveSpring(response: 0.55, dampingFraction: 0.85, blendDuration: 0.3), value: state.value)
                    }
                }
                .clipShape(Capsule())
                
                // Icon & Text overlay
                VStack {
                    if showValue {
                        HUDNumericLabel(
                            value: state.value,
                            font: .system(size: 10, weight: .bold),
                            color: valueLabelColor,
                            alignment: .center,
                            width: hudWidth * 0.8
                        )
                        .padding(.top, 8 + (stretchOffset < 0 ? abs(stretchOffset/4) : 0))
                    }
                    
                    Spacer()
                    
                    Image(systemName: symbolName)
                        .font(.system(size: hudWidth * 0.4, weight: .semibold))
                        .foregroundStyle(state.value > 0.15 ? (useAccentColor ? .white : .black) : .secondary)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.bottom, hudWidth * 0.35)
                        .offset(y: stretchOffset > 0 ? -stretchOffset/4 : 0)
                }
                // Always visible
            }
            .frame(width: currentWidth, height: hudHeight + stretchAmount)
            .offset(y: stretchOffset)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
            .onHover { hovering in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    isHovering = hovering
                }
            }
            // Listen for Elastic Bump (Keyboard) - Debounced via Task cancellation
            .task(id: state.bumpEvent) {
                guard let event = state.bumpEvent else { return }
                
                let direction = CGFloat(event.direction)
                let stretch: CGFloat = 15 // Constant stretch while holding
                
                // Animate In (Maintain Stretch)
                // If a new event comes in, this task is cancelled and restarted, keeping it stretched.
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.6)) {
                    stretchAmount = stretch
                    stretchOffset = direction * (-stretch / 2)
                }
                
                // Wait for key release (Short debounce window)
                try? await Task.sleep(nanoseconds: 150 * 1_000_000) // 150ms
                
                // Animate Back (only if not cancelled)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                    stretchAmount = 0
                    stretchOffset = 0
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isInteractive else { return }
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isDragging = true
                        }
                        
                        let currentY = gesture.startLocation.y + gesture.translation.height
                        let percentage = 1.0 - (currentY / hudHeight)
                        
                        // Elastic Rubber Banding
                        if percentage > 1.0 {
                            let excess = (percentage - 1.0) * hudHeight
                            let stretch = min(sqrt(abs(excess)) * 1.5, maxStretch) // Reduced multiplier (was 3.0)
                            state.value = 1.0
                            
                            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.65)) { // Tighter damping
                                stretchAmount = stretch
                                stretchOffset = -stretch / 2
                            }
                        } else if percentage < 0.0 {
                            let excess = abs(percentage) * hudHeight
                            let stretch = min(sqrt(abs(excess)) * 1.5, maxStretch) // Reduced multiplier
                            state.value = 0.0
                            
                            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.65)) {
                                stretchAmount = stretch
                                stretchOffset = stretch / 2
                            }
                        } else {
                            state.value = percentage
                            withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.8)) {
                                stretchAmount = 0
                                stretchOffset = 0
                            }
                        }
                        updateSystemLevel(state.value)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { // Tighter release
                            isDragging = false
                            stretchAmount = 0
                            stretchOffset = 0
                            if state.value > 1.0 { state.value = 1.0 }
                            if state.value < 0.0 { state.value = 0.0 }
                        }
                        updateSystemLevel(state.value)
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .edgesIgnoringSafeArea(.all)
    }
    
    private var currentWidth: CGFloat {
        // Only shrink slightly when dragging, otherwise full size
        return isDragging ? hudWidth * 0.9 : hudWidth
    }
    
    private func updateSystemLevel(_ level: CGFloat) {
         if state.type == .volume {
              SystemVolumeController.shared.setVolume(Float(level))
         } else if state.type == .brightness {
              SystemBrightnessController.shared.setBrightness(Float(level))
         }
    }
    
    private var symbolName: String {
        if !state.icon.isEmpty { return state.icon }
        
        switch state.type {
        case .volume:
            if state.value < 0.01 { return "speaker.slash.fill" } else if state.value < 0.33 { return "speaker.wave.1.fill" } else if state.value < 0.66 { return "speaker.wave.2.fill" } else { return "speaker.wave.3.fill" }
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return state.value >= 0.5 ? "light.max" : "light.min"
        default:
            return "questionmark"
        }
    }
    
    // MARK: - Helper Computing Properties
    
    private var fillStyle: AnyShapeStyle {
        if state.type == .volume && useColorCodedVolume {
            let intensity = state.value
            if useSmoothGradient {
                let endColor = ColorCodedPalette.color(for: intensity, smooth: true)
                let startColor = ColorCodedPalette.color(for: max(intensity - 0.15, 0), smooth: true)
                return AnyShapeStyle(LinearGradient(colors: [startColor, endColor], startPoint: .bottom, endPoint: .top))
            } else {
                return AnyShapeStyle(ColorCodedPalette.color(for: intensity, smooth: false))
            }
        }
        
        return AnyShapeStyle(useAccentColor ? Color(NSColor.controlAccentColor) : Color.white)
    }

    private var valueLabelColor: Color {
        if state.value > 0.85 {
            return useAccentColor ? .white : .black
        }
        return .secondary
    }

    @ViewBuilder
    private var verticalBackground: some View {
        switch verticalHUDMaterial {
        case .frosted:
            Capsule().fill(.ultraThinMaterial)
        case .liquid:
            if #available(macOS 26.0, *) {
                if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                    LiquidGlassBackground(
                        variant: verticalHUDLiquidGlassVariant,
                        cornerRadius: max(currentWidth, hudWidth)
                    ) {
                        Color.white.opacity(0.04)
                    }
                } else {
                    Capsule()
                        .fill(.clear)
                        .glassEffect(
                            .clear.interactive(),
                            in: .capsule
                        )
                }
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        case .solidDark:
            Capsule().fill(Color.black.opacity(0.85))
        case .solidLight:
            Capsule().fill(Color.white.opacity(0.85))
        case .solidAuto:
            Capsule().fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.85))
        }
    }
}
#endif
