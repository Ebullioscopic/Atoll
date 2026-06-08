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

final class FolderModelsTests: XCTestCase {
    func test_pinnedFolder_codableRoundTrip() throws {
        let original = PinnedFolder(id: UUID(), bookmark: Data([1, 2, 3]), displayName: "Dev")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedFolder.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_folderEntry_identityIsResolvedPath() {
        let url = URL(fileURLWithPath: "/tmp/Example")
        let entry = FolderEntry(url: url, name: "Example", isDirectory: true, modificationDate: nil)
        XCTAssertEqual(entry.id, url.path)
    }

    func test_folderLocation_identityIsResolvedPath() {
        let url = URL(fileURLWithPath: "/tmp/Pinned")
        let loc = FolderLocation(url: url, name: "Pinned", kind: .pinned)
        XCTAssertEqual(loc.id, url.path)
    }
}
