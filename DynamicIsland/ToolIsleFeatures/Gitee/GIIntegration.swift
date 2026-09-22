// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct GITabOverflow: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            ScrollView(.horizontal) {
                content.fixedSize(horizontal: true, vertical: false).padding(.horizontal, 2)
            }
            .scrollIndicators(.visible)
            .frame(height: 32)
            .help("标签较多时可横向滚动；菜单栏也可打开 Gitee Issues")
        } else {
            content
        }
    }
}
