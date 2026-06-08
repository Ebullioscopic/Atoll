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

final class FolderListingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("folderlisting-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("SubDir"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appendingPathComponent("file.txt"))
        try Data().write(to: root.appendingPathComponent(".dotfile"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_contents_returnsEntriesWithDirectoryFlag() throws {
        let entries = try FolderSorting.contents(of: root, fileManager: .default)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
        XCTAssertTrue(byName["SubDir"]?.isDirectory == true)
        XCTAssertTrue(byName["file.txt"]?.isDirectory == false)
        XCTAssertNotNil(byName[".dotfile"], "raw listing includes dotfiles; filtering happens separately")
    }

    func test_contents_throwsForUnreadablePath() {
        let missing = root.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try FolderSorting.contents(of: missing, fileManager: .default))
    }
}
