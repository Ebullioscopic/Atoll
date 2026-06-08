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

/// Backs the "Pin to Atoll" Services-menu entry. Reads folder URLs from the
/// pasteboard and pins them via `FolderLocationsStore`.
final class FolderServiceProvider: NSObject {
    @objc func pinFolderToAtoll(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let folders = urls.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        guard !folders.isEmpty else {
            error?.pointee = NSString(string: "No folder to pin.")
            return
        }
        Task { @MainActor in
            for folder in folders { FolderLocationsStore.shared.pin(folder) }
        }
    }
}
