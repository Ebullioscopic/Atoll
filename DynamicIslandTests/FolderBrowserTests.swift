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
final class FolderBrowserTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("browser-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Inner"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("x".utf8).write(to: root.appendingPathComponent("Inner/b.txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_enter_listsContents_foldersFirst() async {
        let browser = FolderBrowser()
        await browser.enter(root)
        XCTAssertEqual(browser.currentURL, root)
        XCTAssertEqual(browser.entries.map(\.name), ["Inner", "a.txt"])
        XCTAssertTrue(browser.canGoBack)
    }

    func test_drillIn_thenGoBack_restoresParent() async {
        let browser = FolderBrowser()
        await browser.enter(root)
        await browser.enter(root.appendingPathComponent("Inner"))
        XCTAssertEqual(browser.entries.map(\.name), ["b.txt"])
        await browser.goBack()
        XCTAssertEqual(browser.currentURL, root)
        XCTAssertEqual(browser.entries.map(\.name), ["Inner", "a.txt"])
    }

    func test_goBack_fromRoot_clearsToHome() async {
        let browser = FolderBrowser()
        await browser.enter(root)
        await browser.goBack()
        XCTAssertNil(browser.currentURL)
        XCTAssertFalse(browser.canGoBack)
        XCTAssertTrue(browser.entries.isEmpty)
    }

    func test_unreadableDirectory_setsErrorMessage() async {
        let browser = FolderBrowser()
        await browser.enter(root.appendingPathComponent("missing"))
        XCTAssertNotNil(browser.errorMessage)
        XCTAssertTrue(browser.entries.isEmpty)
    }
}
