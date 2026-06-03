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

import SwiftUI

struct DynamicIslandLargeButtons: View {
    var action: () -> Void
    var icon: Image
    var title: String
    var body: some View {
        Button(
            action: action,
            label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12.0).fill(.black).frame(width: 70, height: 70)
                    VStack(spacing: 8) {
                        icon.resizable()
                            .aspectRatio(contentMode: .fit).frame(width: 20)
                        Text(title).font(.body)
                    }
                }
            }).buttonStyle(PlainButtonStyle()).shadow(color: .black.opacity(0.5), radius: 10)
    }
}

struct DynamicIslandExtrasMenu: View {
    @ObservedObject var vm: DynamicIslandViewModel
    
    var body: some View {
        VStack {
            HStack(spacing: 20) {
                hide
                settings
                close
            }
        }
    }
    
    var github: some View {
        DynamicIslandLargeButtons(
            action: {
                NSWorkspace.shared.open(productPage)
            },
            icon: Image(.github),
            title: "Checkout"
        )
    }
    
    var donate: some View {
        DynamicIslandLargeButtons(
            action: {
                NSWorkspace.shared.open(sponsorPage)
            },
            icon: Image(systemName: "heart.fill"),
            title: "Love Us"
        )
    }
    
    var settings: some View {
        Button(action: {
            SettingsWindowController.shared.showWindow()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12.0).fill(.black).frame(width: 70, height: 70)
                VStack(spacing: 8) {
                    Image(systemName: "gear").resizable()
                        .aspectRatio(contentMode: .fit).frame(width: 20)
                    Text("Settings").font(.body)
                }
            }
        }
        .buttonStyle(PlainButtonStyle()).shadow(color: .black.opacity(0.5), radius: 10)
    }
    
    var hide: some View {
        DynamicIslandLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    // vm.openMusic()
                }
            },
            icon: Image(systemName: "arrow.down.forward.and.arrow.up.backward"),
            title: "Hide"
        )
    }
    
    var close: some View {
        DynamicIslandLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NSApp.terminate(nil)
                    }
                }
            },
            icon: Image(systemName: "xmark"),
            title: "Exit"
        )
    }
}

#Preview {
    DynamicIslandExtrasMenu(vm: DynamicIslandViewModel())
}
