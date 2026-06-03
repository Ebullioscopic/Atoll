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

import Cocoa
import Combine
import Foundation
import OrderedCollections

class TrayDrop: ObservableObject {
    static let shared = TrayDrop()

    @Published var items: OrderedSet<DropItem>
    var isEmpty: Bool { items.isEmpty }
    @Published var isLoading: Int = 0

    init(items: OrderedSet<DropItem> = .init(), isLoading: Int = 0) {
        self.items = items
        self.isLoading = isLoading
    }

    func load(_ providers: [NSItemProvider]) {
        assert(!Thread.isMainThread)
        DispatchQueue.main.asyncAndWait { isLoading += 1 }

        guard let urls = providers.interfaceConvert() else {
            DispatchQueue.main.asyncAndWait { isLoading -= 1 }
            print("Failed to load items")
            return
        }
        let dropItems = urls.map { url in
            try? DropItem(url: url)
        }.compactMap { $0 }

        DispatchQueue.main.async {
            dropItems.forEach { self.items.updateOrInsert($0, at: 0) }
            self.isLoading -= 1
        }
        print("DONE")
    }

    func cleanExpiredFiles() {
        var inEdit = items
        let shouldCleanItems = items.filter(\.shouldClean)
        for item in shouldCleanItems {
            inEdit.remove(item)
        }
        items = inEdit
    }

    func delete(_ item: DropItem.ID) {
        guard let item = items.first(where: { $0.id == item }) else { return }
        delete(item: item)
    }

    private func delete(item: DropItem) {
        var inEdit = items

        var url = item.storageURL
        try? FileManager.default.removeItem(at: url)

        do {
            // loops up to the main directory
            url = url.deletingLastPathComponent()
            while url.lastPathComponent != DropItem.mainDir, url != documentsDirectory {
                let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
                guard contents.isEmpty else { break }
                try FileManager.default.removeItem(at: url)
                url = url.deletingLastPathComponent()
            }
        } catch {}

        inEdit.remove(item)
        items = inEdit
    }

    func removeAll() {
        items.forEach { delete(item: $0) }
    }
}

