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

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .white
    var scale: Image.Scale = .medium
    var pressEffect: PressEffect? = nil
    var contentTransition: ContentTransition = .symbolEffect
    var externalTriggerToken: Int? = nil
    var externalTriggerEffect: PressEffect? = nil
    /// When set, the button draws an animated skip glyph instead of `icon`:
    /// the chevrons march in this direction the way Apple's do, and the button
    /// itself stays put.
    var skipDirection: SkipTrackGlyph.Direction? = nil
    var action: () -> Void
    
    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var skipToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            if let skipDirection {
                                SkipTrackGlyph(
                                    direction: skipDirection,
                                    size: glyphPointSize,
                                    trigger: skipToken
                                )
                                .foregroundStyle(iconColor)
                            } else {
                                let baseImage = Image(systemName: icon)
                                    .foregroundColor(iconColor)
                                    .contentTransition(contentTransition)
                                    .font(scale == .large ? .largeTitle : .body)

                                if case .wiggle = pressEffect {
                                    if #available(macOS 15.0, *) {
                                        baseImage
                                            .symbolEffect(
                                                .wiggle.byLayer,
                                                options: .nonRepeating,
                                                value: wiggleToken
                                            )
                                    } else {
                                        baseImage
                                    }
                                } else {
                                    baseImage
                                }
                            }
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(wiggleAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    /// Point size the skip glyph is drawn at, matched to the text style the
    /// symbol would otherwise use so it sits like the icon it replaces.
    private var glyphPointSize: CGFloat {
        NSFont.preferredFont(forTextStyle: scale == .large ? .largeTitle : .body).pointSize
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        // Fires for taps and for gesture-driven pulses alike, and independently
        // of pressEffect — skip buttons no longer use one.
        if skipDirection != nil {
            skipToken += 1
        }

        guard let effect = override ?? pressEffect else { return }

        switch effect {
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
                wiggleAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    wiggleAngle = 0
                }
            }
        }
    }

    enum PressEffect {
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
