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

final class FolderSortingTests: XCTestCase {
    private func entry(_ name: String, dir: Bool, mod: Date? = nil) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, isDirectory: dir, modificationDate: mod)
    }

    func test_sort_foldersBeforeFiles_thenNameAscending() {
        let input = [entry("zeta", dir: false), entry("Beta", dir: true), entry("alpha", dir: false), entry("Alpha", dir: true)]
        let result = FolderSorting.sort(input, by: .nameAsc).map(\.name)
        XCTAssertEqual(result, ["Alpha", "Beta", "alpha", "zeta"])
    }

    func test_sort_byDateModifiedDescending_withinSameKind() {
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        let input = [entry("old.txt", dir: false, mod: old), entry("new.txt", dir: false, mod: new)]
        let result = FolderSorting.sort(input, by: .dateModifiedDesc).map(\.name)
        XCTAssertEqual(result, ["new.txt", "old.txt"])
    }

    func test_filterHidden_dropsDotfiles_whenDisabled() {
        let input = [entry(".hidden", dir: false), entry("visible", dir: false)]
        XCTAssertEqual(FolderSorting.filterHidden(input, showHidden: false).map(\.name), ["visible"])
    }

    func test_filterHidden_keepsDotfiles_whenEnabled() {
        let input = [entry(".hidden", dir: false), entry("visible", dir: false)]
        XCTAssertEqual(FolderSorting.filterHidden(input, showHidden: true).map(\.name).sorted(), [".hidden", "visible"])
    }
}
