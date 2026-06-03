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

import Foundation
import SwiftUI

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.2),
                    lineWidth: 6
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    // 1
                    style: StrokeStyle(
                        lineWidth: 6,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

enum ProgressIndicatorType {
    case circle
    case text
}

    // based on type .circle or .text
struct ProgressIndicator: View {
    var type: ProgressIndicatorType
    var progress: Double
    var color: Color
    
    var body: some View {
        switch type {
            case .circle:
                CircularProgressView(progress: progress, color: color).frame(
                width: 20, height: 20)
            case .text:
                Text("\(Int(progress * 100))%")
        }
    }
}

#Preview {
    ProgressIndicator(type: .circle, progress: 0.8, color: Color.blue).padding()
        .frame(width: 200, height: 200)
}
