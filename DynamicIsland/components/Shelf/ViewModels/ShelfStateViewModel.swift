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

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet {
            ShelfPersistenceService.shared.save(items)
            ShelfSelectionModel.shared.reconcileSelection(with: items)
        }
    }

    @Published var isLoading: Bool = false

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: (bookmark: Data, path: String?, source: Data)] = [:]
    private var updateTask: Task<Void, Never>?
    
    // Cache for URL-to-item mapping to avoid resolving all bookmarks for lookup
    private var urlToItemCache: [String: ShelfItem.ID] = [:]
    private var urlCacheInvalidated = true

    private init() {
        items = ShelfPersistenceService.shared.load()
        backfillCachedPaths()
    }

    /// Resolves `cachedPath` for items persisted before the path cache existed,
    /// off the main actor. Once this lands, `identityKey` and `resolvedFileURL`
    /// never touch the disk on the main actor — which is what keeps an
    /// unreachable network mount from stalling the UI.
    private func backfillCachedPaths() {
        let pending: [(ShelfItem.ID, Data)] = items.compactMap { item in
            guard item.cachedPath == nil, case .file(let data) = item.kind else { return nil }
            return (item.id, data)
        }
        guard !pending.isEmpty else { return }

        Task.detached(priority: .utility) {
            var resolved: [ShelfItem.ID: String] = [:]
            var sources: [ShelfItem.ID: Data] = [:]
            for (itemID, data) in pending {
                if let url = Bookmark(data: data).resolve().url {
                    resolved[itemID] = url.standardizedFileURL.path
                    sources[itemID] = data
                }
            }
            guard !resolved.isEmpty else { return }
            // Hand the closure immutable copies: capturing the `var`s directly is
            // already a warning and becomes an error in the Swift 6 language mode.
            let paths = resolved
            let bookmarks = sources
            await MainActor.run {
                ShelfStateViewModel.shared.applyCachedPaths(paths, resolvedFrom: bookmarks)
            }
        }
    }

    /// Applies resolved paths in a single mutation — writing `items[idx]` inside
    /// a loop would fire `didSet` (and a full JSON save) once per item.
    ///
    /// `sources` carries the bookmark each path was resolved from, and an entry
    /// only lands while the item still holds that bookmark. Every caller resolves
    /// off the main actor, so a resolve that started before a rename can finish
    /// *after* `updateBookmark` recorded the new bookmark and path; without the
    /// check it would put the pre-rename path back, and `resolvedFileURL` prefers
    /// `cachedPath` — so drag-out and the context menu would target the old
    /// location.
    func applyCachedPaths(_ paths: [ShelfItem.ID: String], resolvedFrom sources: [ShelfItem.ID: Data]) {
        guard !paths.isEmpty else { return }
        var updated = items
        var changed = false
        for idx in updated.indices {
            let id = updated[idx].id
            guard let path = paths[id], updated[idx].cachedPath != path else { continue }
            guard case .file(let current) = updated[idx].kind, current == sources[id] else { continue }
            updated[idx].cachedPath = path
            changed = true
        }
        if changed {
            items = updated
            invalidateURLCache()
        }
    }

    func applyCachedPath(_ path: String, for itemID: ShelfItem.ID, resolvedFrom source: Data) {
        applyCachedPaths([itemID: path], resolvedFrom: [itemID: source])
    }

    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        var addedIDs: [String] = []
        for it in newItems where seen.insert(it.identityKey).inserted {
            merged.append(it)
            addedIDs.append(it.id.uuidString)
        }
        // Every duplicate-only drop would otherwise trigger a save and a publish.
        guard !addedIDs.isEmpty else { return }
        items = merged
        invalidateURLCache()
        ExtensionRPCServer.shared.notifyShelfItemsChanged(itemIDs: addedIDs, action: "added")
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
        invalidateURLCache()
        ExtensionRPCServer.shared.notifyShelfItemsChanged(itemIDs: [item.id.uuidString], action: "removed")
    }

    /// Pass `path` whenever the caller already resolved the new bookmark —
    /// leaving `cachedPath` pointing at the old location would make dedup treat
    /// a renamed file as a new one.
    ///
    /// Pass `resolvedFrom` when `bookmark` is the *refreshed form of an older
    /// bookmark* obtained off the main actor: the write is then skipped unless the
    /// item still holds that older bookmark, so a resolve that began before a
    /// rename cannot put the pre-rename bookmark and path back. Omit it for
    /// authoritative writes — the rename flow has already moved the file on disk,
    /// and its data is by definition the freshest, so discarding that write
    /// because something else refreshed the bookmark while the save panel was
    /// open would lose the rename instead of protecting it.
    func updateBookmark(for item: ShelfItem, bookmark: Data, path: String? = nil, resolvedFrom source: Data? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard case .file(let current) = items[idx].kind else { return }
        if let source, current != source { return }
        let newPath = path ?? Bookmark(data: bookmark).resolveWithoutMounting()?.standardizedFileURL.path
        // `items.didSet` writes the whole shelf JSON, so mutating `kind` and
        // `cachedPath` as two statements saves twice and — in between — persists
        // the new bookmark paired with the old path.
        var updated = items
        updated[idx].kind = .file(bookmark: bookmark)
        updated[idx].cachedPath = newPath
        items = updated
        invalidateURLCache()
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data, path: String?, resolvedFrom source: Data) {
        pendingBookmarkUpdates[item.id] = (bookmark, path, source)

        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()

            guard let self = self else { return }

            let updates = self.pendingBookmarkUpdates
            self.pendingBookmarkUpdates.removeAll()
            guard !updates.isEmpty else { return }

            // Same reason as `updateBookmark`: one assignment, so the coalesced
            // batch costs a single save instead of two per item.
            var updated = self.items
            var changed = false
            for (itemID, update) in updates {
                guard let idx = updated.firstIndex(where: { $0.id == itemID }),
                      case .file(let current) = updated[idx].kind else { continue }
                // Revalidated after the suspension above, not just at schedule
                // time: the item may have been renamed while this was queued, in
                // which case the refresh is a resolve of the pre-rename bookmark.
                guard current == update.source else { continue }
                updated[idx].kind = .file(bookmark: update.bookmark)
                if let path = update.path { updated[idx].cachedPath = path }
                changed = true
            }

            guard changed else { return }
            self.items = updated
            self.invalidateURLCache()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
                self?.isLoading = false
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }

    // Async version that resolves bookmark on background thread
    func resolveFileURLAsync(for item: ShelfItem) async -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = await bookmark.resolveAsync()
        let path = result.url?.standardizedFileURL.path
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            await MainActor.run {
                scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed, path: path, resolvedFrom: bookmarkData)
            }
        } else if let path {
            // Self-healing: the file may have moved since the path was cached.
            await MainActor.run { applyCachedPath(path, for: item.id, resolvedFrom: bookmarkData) }
        }
        return result.url
    }

    // Async version for user-initiated actions
    func resolveAndUpdateBookmarkAsync(for item: ShelfItem) async -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = await bookmark.resolveAsync()
        let path = result.url?.standardizedFileURL.path
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            await MainActor.run {
                updateBookmark(for: item, bookmark: refreshed, path: path, resolvedFrom: bookmarkData)
            }
        } else if let path {
            await MainActor.run { applyCachedPath(path, for: item.id, resolvedFrom: bookmarkData) }
        }
        return result.url
    }

    // Find item by URL using cached mapping (avoids resolving all bookmarks)
    func findItem(by url: URL) async -> ShelfItem? {
        let path = url.standardizedFileURL.path
        if urlCacheInvalidated {
            await rebuildURLCache()
        }
        if let itemID = urlToItemCache[path],
           let idx = items.firstIndex(where: { $0.id == itemID }) {
            return items[idx]
        }
        // Fallback: async resolution for cache miss
        for itm in items {
            if case .file = itm.kind {
                if let resolved = await resolveFileURLAsync(for: itm),
                   resolved.standardizedFileURL.path == path {
                    return itm
                }
            }
        }
        return nil
    }

    private func rebuildURLCache() async {
        urlToItemCache.removeAll()
        for item in items {
            if case .file(let bookmarkData) = item.kind {
                let bookmark = Bookmark(data: bookmarkData)
                let result = await bookmark.resolveAsync()
                if let url = result.url {
                    urlToItemCache[url.standardizedFileURL.path] = item.id
                }
            }
        }
        urlCacheInvalidated = false
    }
    
    private func invalidateURLCache() {
        urlCacheInvalidated = true
    }

    // Async version - resolves file URLs without blocking
    func resolveFileURLsAsync(for items: [ShelfItem]) async -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = await resolveFileURLAsync(for: it) { urls.append(u) }
        }
        return urls
    }
}
