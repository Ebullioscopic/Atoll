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
import Combine
import Defaults
import Foundation

/// Navigates one directory tree at a time: a push/pop stack, listing the current
/// directory, and open/reveal actions. Knows nothing about pins or shortcuts.
@MainActor
final class FolderBrowser: ObservableObject {
    @Published private(set) var stack: [URL] = []
    @Published private(set) var entries: [FolderEntry] = []
    @Published private(set) var errorMessage: String?

    var currentURL: URL? { stack.last }
    var canGoBack: Bool { !stack.isEmpty }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Push a directory onto the stack and list it.
    func enter(_ url: URL) async {
        stack.append(url)
        await refresh()
    }

    /// Pop the current directory. At root, clears back to the home screen.
    func goBack() async {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        if currentURL != nil {
            await refresh()
        } else {
            entries = []
            errorMessage = nil
        }
    }

    /// Clear all navigation state (return to home).
    func reset() {
        stack = []
        entries = []
        errorMessage = nil
    }

    /// Re-list the current directory, applying the user's sort + hidden-file preferences.
    /// Lists synchronously on the main actor (FileManager is not Sendable); directory
    /// listings are fast for typical sizes.
    func refresh() async {
        guard let url = currentURL else {
            entries = []
            return
        }
        let showHidden = Defaults[.foldersShowHidden]
        let sortMode = Defaults[.foldersSortMode]
        do {
            let raw = try FolderSorting.contents(of: url, fileManager: fileManager)
            let filtered = FolderSorting.filterHidden(raw, showHidden: showHidden)
            entries = FolderSorting.sort(filtered, by: sortMode)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = String(localized: "Can’t open this folder.")
        }
    }

    /// Open a file in its default app, or drill into a directory.
    func activate(_ entry: FolderEntry) async {
        if entry.isDirectory {
            await enter(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    /// Reveal the current directory in Finder.
    func revealCurrentInFinder() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
