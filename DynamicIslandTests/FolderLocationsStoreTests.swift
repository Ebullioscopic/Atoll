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
final class FolderLocationsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var dirA: URL!
    private var dirB: URL!

    override func setUpWithError() throws {
        suiteName = "folders-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("locstore-\(UUID().uuidString)")
        dirA = base.appendingPathComponent("A")
        dirB = base.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dirA.deletingLastPathComponent())
    }

    func test_pin_addsResolvedLocation() {
        let store = FolderLocationsStore(defaults: defaults)
        store.pin(dirA)
        XCTAssertEqual(store.pinned.map(\.url.path), [dirA.path])
        XCTAssertEqual(store.pinned.first?.kind, .pinned)
    }

    func test_pin_isIdempotentByPath() {
        let store = FolderLocationsStore(defaults: defaults)
        store.pin(dirA)
        store.pin(dirA)
        XCTAssertEqual(store.pinned.count, 1)
    }

    func test_unpin_removesLocation() {
        let store = FolderLocationsStore(defaults: defaults)
        store.pin(dirA)
        store.pin(dirB)
        let idA = store.pinned.first { $0.url.path == dirA.path }!.id
        store.unpin(id: idA)
        XCTAssertEqual(store.pinned.map(\.url.path), [dirB.path])
    }

    func test_pins_persistAcrossInstances() {
        let store1 = FolderLocationsStore(defaults: defaults)
        store1.pin(dirA)
        let store2 = FolderLocationsStore(defaults: defaults)
        XCTAssertEqual(store2.pinned.map(\.url.path), [dirA.path])
    }

    func test_loadPinned_prunesDeletedFolder() throws {
        let store1 = FolderLocationsStore(defaults: defaults)
        store1.pin(dirB)
        try FileManager.default.removeItem(at: dirB)
        let store2 = FolderLocationsStore(defaults: defaults)
        XCTAssertTrue(store2.pinned.isEmpty, "a pin whose folder no longer resolves is not displayed")
    }
}
