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

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }

    static func items(from fileURLs: [URL]) async -> [ShelfItem] {
        var results: [ShelfItem] = []
        let fileManager = FileManager.default

        for fileURL in fileURLs {
            let resolvedURL = fileURL.standardizedFileURL
            guard resolvedURL.isFileURL else { continue }
            guard fileManager.fileExists(atPath: resolvedURL.path) else {
                NSLog("⚠️ Ignoring non-existent file URL: \(resolvedURL.path)")
                continue
            }

            if let item = await fileItem(for: resolvedURL, isTemporary: false) {
                results.append(item)
            }
        }

        return results
    }

    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            return await fileItem(for: actualFileURL, isTemporary: false)
        }

        if let url = await provider.extractURL() {
            if url.isFileURL {
                return await fileItem(for: url, isTemporary: false)
            }
            return await ShelfItem(kind: .link(url: url), isTemporary: false)
        }

        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }

        if let data = await provider.loadData() {
            guard let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)) else {
                return nil
            }
            return await fileItem(for: tempDataURL, isTemporary: true)
        }

        if let fileURL = await provider.extractItem() {
            return await fileItem(for: fileURL, isTemporary: false)
        }

        return nil
    }

    /// Builds a `.file` item, recording the path alongside the bookmark so that
    /// dedup, drag-out and the context menu never have to resolve the bookmark
    /// on the main actor.
    private static func fileItem(for url: URL, isTemporary: Bool) async -> ShelfItem? {
        guard let bookmark = createBookmark(for: url) else { return nil }
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let name = standardized.lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: path)
        let iconData = compactIconData(for: icon)
        return await ShelfItem(
            kind: .file(bookmark: bookmark),
            isTemporary: isTemporary,
            cachedDisplayName: name,
            cachedIconData: iconData,
            cachedPath: path
        )
    }

    /// Generates a compact PNG representation of the specified icon scaled to target dimensions.
    /// - Parameters:
    ///   - icon: The source NSImage to render.
    ///   - targetSize: Desired thumbnail size in points; defaults to 64x64.
    /// - Returns: Compressed PNG data, or `nil` if rendering fails.
    private static func compactIconData(for icon: NSImage, targetSize: NSSize = NSSize(width: 64, height: 64)) -> Data? {
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }
}
