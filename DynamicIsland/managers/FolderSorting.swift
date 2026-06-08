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

/// Pure, side-effect-free helpers for ordering and filtering folder entries.
enum FolderSorting {
    /// Folders always sort before files; within each kind, by the given mode.
    static func sort(_ entries: [FolderEntry], by mode: FolderSortMode) -> [FolderEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            switch mode {
            case .nameAsc:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .dateModifiedDesc:
                let l = lhs.modificationDate ?? .distantPast
                let r = rhs.modificationDate ?? .distantPast
                if l == r {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return l > r
            }
        }
    }

    /// Drops dotfiles unless `showHidden` is true.
    static func filterHidden(_ entries: [FolderEntry], showHidden: Bool) -> [FolderEntry] {
        showHidden ? entries : entries.filter { !$0.name.hasPrefix(".") }
    }

    /// Lists a directory's immediate contents as `FolderEntry` values.
    /// Returns the raw, unsorted, unfiltered set — callers apply `sort`/`filterHidden`.
    /// Throws if the directory cannot be read.
    static func contents(of directory: URL, fileManager: FileManager) throws -> [FolderEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .localizedNameKey, .nameKey]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.localizedName ?? values?.name ?? url.lastPathComponent
            return FolderEntry(
                url: url,
                name: name,
                isDirectory: values?.isDirectory ?? false,
                modificationDate: values?.contentModificationDate
            )
        }
    }
}
