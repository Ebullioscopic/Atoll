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

import AppKit
import Defaults
import SwiftUI

struct FoldersSettings: View {
    @Default(.enableFoldersFeature) private var enableFolders
    @Default(.foldersShowSystemShortcuts) private var showShortcuts
    @Default(.foldersShowRecentFiles) private var showRecentFiles
    @Default(.foldersShowRecentDownloads) private var showRecentDownloads
    @Default(.foldersShowHidden) private var showHidden
    @Default(.foldersSortMode) private var sortMode
    @Default(.foldersRecentLimit) private var recentLimit

    @ObservedObject private var store = FolderLocationsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Enable Folders tab"), isOn: $enableFolders)
            }
            Section(String(localized: "Sections")) {
                Toggle(String(localized: "System shortcuts"), isOn: $showShortcuts)
                Toggle(String(localized: "Recent files"), isOn: $showRecentFiles)
                Toggle(String(localized: "Recent downloads"), isOn: $showRecentDownloads)
            }
            Section(String(localized: "Browsing")) {
                Picker(String(localized: "Default sort"), selection: $sortMode) {
                    Text(String(localized: "Name")).tag(FolderSortMode.nameAsc)
                    Text(String(localized: "Date modified")).tag(FolderSortMode.dateModifiedDesc)
                }
                Toggle(String(localized: "Show hidden files"), isOn: $showHidden)
                Stepper(value: $recentLimit, in: 5...30) {
                    Text("Recent items shown: \(recentLimit)")
                }
            }
            Section(String(localized: "Pinned Folders")) {
                if store.pinned.isEmpty {
                    Text(String(localized: "Drag a folder onto the notch, or right-click a folder in Finder ▸ Services ▸ Pin to Atoll."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.pinned) { location in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: location.url.path))
                                .resizable().frame(width: 16, height: 16)
                            Text(location.name)
                            Spacer()
                            Button(role: .destructive) { store.unpin(id: location.id) } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button(String(localized: "Add Folder…")) { addFolder() }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshShortcuts() }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.pin(url)
        }
    }
}
