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

/// Shared numeric label for HUD/OSD styles with rolling value animation.
struct HUDNumericLabel: View {
    let value: CGFloat
    var font: Font
    var color: Color
    var alignment: Alignment = .center
    var width: CGFloat?
    var minimumDigits: Int = 3
    var animation: Animation = .interactiveSpring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.15)
    
    @State private var animatedValue: CGFloat = 0
    
    var body: some View {
        Text(formattedValue)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .frame(width: width, alignment: alignment)
            .onAppear {
                animatedValue = value
            }
            .onChange(of: value) { newValue in
                withAnimation(animation) {
                    animatedValue = newValue
                }
            }
    }
    
    private var formattedValue: String {
        let clamped = max(0, min(100, Int(round(animatedValue * 100))))
        let digits = max(1, minimumDigits)
        let format = "%\(digits)d"
        return String(format: format, clamped)
    }
}
#endif
