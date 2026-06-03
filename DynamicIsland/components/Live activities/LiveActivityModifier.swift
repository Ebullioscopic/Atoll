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

enum ActivityType {
    case mediaPlayback
    case charging
    case download
}

struct LiveActivityModifier<Left: View, Right: View>: ViewModifier {
    let `for`: ActivityType
    let leftContent: () -> Left
    let rightContent: () -> Right
    
    func body(content: Content) -> some View {
        content
            .overlay(
                HStack {
                    leftContent()
                    Spacer()
                        // .frame(minWidth: vm.closedNotchSize.width)
                    rightContent()
                }
                .padding()
            )
    }
}

extension View {
    func liveActivity<Left: View, Right: View>(
        for activityId: ActivityType,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) -> some View {
        self.modifier(LiveActivityModifier(for: activityId, leftContent: left, rightContent: right))
    }
}
