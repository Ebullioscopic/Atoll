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

import XCTest
@testable import Atoll

@MainActor
final class FolderShortcutsTests: XCTestCase {
    func test_buildShortcuts_includesStandardLocations() {
        let store = FolderLocationsStore(defaults: UserDefaults(suiteName: "sc-\(UUID().uuidString)")!)
        store.refreshShortcuts()
        let names = Set(store.shortcuts.map(\.name))
        XCTAssertTrue(store.shortcuts.allSatisfy { $0.kind == .shortcut })
        XCTAssertFalse(store.shortcuts.isEmpty)
        XCTAssertTrue(names.contains("Downloads") || names.contains("Desktop"))
    }

    func test_recentDownloads_sortedByAddedDateDescending_limited() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = ["first.bin", "second.bin", "third.bin"]
        for (i, n) in names.enumerated() {
            let u = dir.appendingPathComponent(n)
            try Data().write(to: u)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1000 + Double(i) * 100)], ofItemAtPath: u.path)
        }
        let store = FolderLocationsStore(defaults: UserDefaults(suiteName: "dl-\(UUID().uuidString)")!)
        let result = store.recentDownloadLocations(in: dir, limit: 2)
        XCTAssertEqual(result.map(\.name), ["third.bin", "second.bin"])
        XCTAssertTrue(result.allSatisfy { $0.kind == .recentDownload })
        XCTAssertTrue(result.allSatisfy { !$0.isDirectory })
    }
}
