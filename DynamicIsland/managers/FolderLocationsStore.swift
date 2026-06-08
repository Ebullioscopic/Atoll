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

import Combine
import Foundation

/// Owns "what locations exist": pinned folders (persisted), system shortcuts,
/// recent files, and recent downloads. Pure data + persistence; no directory
/// navigation. Side-effecty discovery (Spotlight, Downloads scan) is behind
/// explicit `start()` / `refresh*()` methods, never in `init`, so the unit
/// constructs cleanly in tests.
@MainActor
final class FolderLocationsStore: ObservableObject {
    static let shared = FolderLocationsStore()

    @Published private(set) var pinned: [FolderLocation] = []
    @Published private(set) var shortcuts: [FolderLocation] = []
    @Published private(set) var recentFiles: [FolderLocation] = []
    @Published private(set) var recentDownloads: [FolderLocation] = []

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let pinsKey = "pinnedFolders"   // raw [Data] of bookmark blobs
    private var metadataQuery: NSMetadataQuery?
    private var recentFilesLimit = 10

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        loadPinned()
    }

    // MARK: - Pins

    /// Persisted bookmark blobs.
    private var pinBookmarks: [Data] {
        get { (defaults.array(forKey: pinsKey) as? [Data]) ?? [] }
        set { defaults.set(newValue, forKey: pinsKey) }
    }

    /// Pin a folder. De-dupes by resolved path; persists a bookmark.
    func pin(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !pinned.contains(where: { $0.url.path == standardized.path }) else { return }
        guard let bookmark = try? standardized.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        pinBookmarks.append(bookmark)
        loadPinned()
    }

    /// Remove a pin by its resolved-path id.
    func unpin(id: String) {
        var survivors: [Data] = []
        for blob in pinBookmarks {
            if let url = Self.resolve(blob), url.path == id { continue }
            survivors.append(blob)
        }
        pinBookmarks = survivors
        loadPinned()
    }

    /// Resolve stored bookmarks into `pinned`.
    /// A bookmark is pruned from storage only when it can no longer be resolved at all.
    /// A pin whose folder is temporarily unavailable (e.g. an unmounted external/network
    /// volume) still resolves, so we keep it in storage and simply omit it from the
    /// displayed list until it returns — rather than destroying the pin.
    func loadPinned() {
        var resolved: [FolderLocation] = []
        var survivingBlobs: [Data] = []
        for blob in pinBookmarks {
            guard let url = Self.resolve(blob) else { continue }
            survivingBlobs.append(blob)
            if fileManager.fileExists(atPath: url.path) {
                resolved.append(FolderLocation(url: url, name: url.lastPathComponent, kind: .pinned))
            }
        }
        if survivingBlobs.count != pinBookmarks.count {
            pinBookmarks = survivingBlobs
        }
        pinned = resolved
    }

    private static func resolve(_ blob: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: blob,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url.standardizedFileURL
    }

    // MARK: - System shortcuts

    /// Standard Finder-sidebar locations that resolve on this account.
    func refreshShortcuts() {
        var result: [FolderLocation] = []
        func add(_ url: URL?, _ fallbackName: String) {
            guard let url, fileManager.fileExists(atPath: url.path) else { return }
            let name = url.lastPathComponent.isEmpty ? fallbackName : url.lastPathComponent
            result.append(FolderLocation(url: url, name: name, kind: .shortcut))
        }
        add(URL(fileURLWithPath: NSHomeDirectory()), "Home")
        add(try? fileManager.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false), "Desktop")
        add(try? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false), "Documents")
        add(try? fileManager.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false), "Downloads")
        add(try? fileManager.url(for: .applicationDirectory, in: .localDomainMask, appropriateFor: nil, create: false), "Applications")
        shortcuts = result
    }

    // MARK: - Recent downloads

    /// Newest items in a downloads directory, by modification date, descending.
    func recentDownloadLocations(in directory: URL, limit: Int) -> [FolderLocation] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .localizedNameKey, .nameKey, .isDirectoryKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return [] }
        let dated = urls.map { url -> (URL, Date, String, Bool) in
            let v = try? url.resourceValues(forKeys: keys)
            return (url,
                    v?.contentModificationDate ?? .distantPast,
                    v?.localizedName ?? v?.name ?? url.lastPathComponent,
                    v?.isDirectory ?? false)
        }
        return dated
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { FolderLocation(url: $0.0, name: $0.2, kind: .recentDownload, isDirectory: $0.3) }
    }

    /// Refresh `recentDownloads` from ~/Downloads.
    func refreshRecentDownloads(limit: Int) {
        guard let downloads = try? fileManager.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            recentDownloads = []
            return
        }
        recentDownloads = recentDownloadLocations(in: downloads, limit: limit)
    }

    // MARK: - Recent files (Spotlight)

    /// Start a live Spotlight query for recently-used files. Results land in `recentFiles`.
    /// Verified manually (Spotlight is environment-dependent and out of unit-test scope).
    func startRecentFilesQuery(limit: Int) {
        stopRecentFilesQuery()
        recentFilesLimit = limit
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "kMDItemContentTypeTree != 'public.folder' && kMDItemLastUsedDate > %@",
                                      Date(timeIntervalSinceNow: -60 * 60 * 24 * 30) as NSDate)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        NotificationCenter.default.addObserver(
            self, selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate, object: query)
        metadataQuery = query
        query.start()
    }

    func stopRecentFilesQuery() {
        if let query = metadataQuery {
            query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        }
        metadataQuery = nil
    }

    @objc private func metadataQueryDidUpdate(_ note: Notification) {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var result: [FolderLocation] = []
        for i in 0..<min(query.resultCount, recentFilesLimit * 3) where result.count < recentFilesLimit {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: path), !path.contains("/.Trash/") else { continue }
            let name = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String) ?? url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            result.append(FolderLocation(url: url, name: name, kind: .recentFile, isDirectory: isDir))
        }
        recentFiles = result
    }

    /// Discover everything that is not a pin. Called from the view on appear.
    func start(recentLimit: Int) {
        refreshShortcuts()
        refreshRecentDownloads(limit: recentLimit)
        startRecentFilesQuery(limit: recentLimit)
    }
}
