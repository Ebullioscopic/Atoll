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
import TipKit

struct HUDsTip: Tip {
    var title: Text {
        Text("Enhance your experience with HUDs")
    }
    
    var message: Text? {
        Text("Unlock advanced features and improve your experience. Upgrade now for more customizations!")
    }
    
    var image: Image? {
        AppIcon(for: "dynamicisland.DynamicIsland")
    }
    
    var actions: [Action] {
        Action {
            Text("More")
        }
    }
}

struct CBTip: Tip {
    var title: Text {
        Text("Boost your productivity with Clipboard Manager")
    }
    
    var message: Text? {
        Text("Easily copy, store, and manage your most-used content. Upgrade now for advanced features like multi-item storage and quick access!")
    }
    
    var image: Image? {
        AppIcon(for: "dynamicisland.DynamicIsland")
    }
    
    var actions: [Action] {
        Action {
            Text("More")
        }
    }
}

struct TipsView: View {
    var hudTip = HUDsTip()
    var cbTip = CBTip()
    var body: some View {
        VStack {
            TipView(hudTip)
            TipView(cbTip)
        }
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
        }
    }
}

#Preview {
    TipsView()
}
