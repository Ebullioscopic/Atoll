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

import Foundation
import AppKit

struct Bookmark: Sendable, Equatable, Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "Bookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a valid file URL or file does not exist at \(url.path)"])
        }
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            NSLog("✅ Successfully created bookmark for \(url.path)")
            self.data = bookmark
        } catch {
            NSLog("❌ Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            throw error
        }
    }

    func resolveAsync() async -> (url: URL?, refreshedData: Data?) {
        guard !data.isEmpty else { return (nil, nil) }
        return await Task.detached(priority: .userInitiated) { [data] in
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale, let newData = try? url.bookmarkData(options: [.withSecurityScope]) {
                    NSLog("⚠️ Bookmark was stale for \(url.path), refreshed")
                    return (url, newData)
                }
                return (url, nil)
            } catch {
                NSLog("❌ Failed to resolve bookmark asynchronously: \(error.localizedDescription)")
                return (nil, nil)
            }
        }.value
    }

    func resolveURL() -> URL? {
        return resolve().url
    }

    func resolve() -> (url: URL?, refreshedData: Data?) {
        guard !data.isEmpty else { return (nil, nil) }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale, let newData = try? url.bookmarkData(options: [.withSecurityScope]) {
                NSLog("⚠️ Bookmark was stale for \(url.path), refreshed")
                return (url, newData)
            }
            return (url, nil)
        } catch {
            NSLog("❌ Failed to resolve bookmark: \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    func validate() async -> Bool {
        let (url, _) = await resolveAsync()
        guard let url = url else { return false }
        return url.accessSecurityScopedResource { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    func withAccess<T: Sendable>(_ block: @Sendable (URL) async throws -> T) async rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try await url.accessSecurityScopedResource { url in
            try await block(url)
        }
    }

    func withAccess<T>(_ block: (URL) throws -> T) rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try url.accessSecurityScopedResource { url in
            try block(url)
        }
    }
}