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

import Foundation
import Defaults

/// Where a `FolderLocation` came from, for section grouping in the UI.
enum FolderLocationKind: Equatable {
    case pinned
    case shortcut
    case recentFile
    case recentDownload
}

/// Sort order for directory entries.
enum FolderSortMode: String, Codable, CaseIterable, Defaults.Serializable {
    case nameAsc
    case dateModifiedDesc
}

/// A user-pinned folder, persisted as a bookmark.
struct PinnedFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let bookmark: Data
    var displayName: String

    init(id: UUID = UUID(), bookmark: Data, displayName: String) {
        self.id = id
        self.bookmark = bookmark
        self.displayName = displayName
    }
}

/// A top-level entry on the Folders "home" screen.
/// Not persisted — assembled at runtime from bookmarks / FileManager.
struct FolderLocation: Identifiable, Equatable {
    let id: String          // resolved path — stable identity
    let url: URL
    let name: String
    let kind: FolderLocationKind
    let isDirectory: Bool

    init(url: URL, name: String, kind: FolderLocationKind, isDirectory: Bool = true) {
        self.id = url.path
        self.url = url
        self.name = name
        self.kind = kind
        self.isDirectory = isDirectory
    }
}

/// A single row inside the directory browser.
/// Not persisted — assembled at runtime from bookmarks / FileManager.
struct FolderEntry: Identifiable, Equatable {
    let id: String          // resolved path — stable identity
    let url: URL
    let name: String
    let isDirectory: Bool
    let modificationDate: Date?

    init(url: URL, name: String, isDirectory: Bool, modificationDate: Date?) {
        self.id = url.path
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
    }
}
