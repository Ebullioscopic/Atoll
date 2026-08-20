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

import Defaults
import XCTest

@testable import Atoll

/// "Save History Across Restarts" is a privacy promise, so the parts that make
/// it true are worth pinning down: nothing written while it is off, nothing
/// left behind when it is turned off, and — the part that is easy to miss —
/// image bytes staying out of `clipboardDataDirectory` as well as out of
/// `UserDefaults`.
@MainActor
final class ClipboardHistoryPersistenceTests: XCTestCase {
    private let historyKey = "ClipboardHistory"
    private var originalSetting = true

    override func setUp() {
        super.setUp()
        originalSetting = Defaults[.persistClipboardHistory]
    }

    override func tearDown() {
        Defaults[.persistClipboardHistory] = originalSetting
        super.tearDown()
    }

    private func makeImageData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemPink.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        return png
    }

    private func imageFilesOnDisk() -> Set<String> {
        let contents = try? FileManager.default.contentsOfDirectory(
            atPath: ClipboardManager.clipboardDataDirectory.path
        )
        return Set(contents ?? [])
    }

    // MARK: - Image bytes

    /// The setting's wording promises nothing reaches disk. A PNG of whatever
    /// was copied is the most sensitive thing here, and it used to be written
    /// unconditionally.
    func testImageCopyWritesNoFileWhilePersistenceIsOff() {
        Defaults[.persistClipboardHistory] = false
        let before = imageFilesOnDisk()

        let item = ClipboardItem(imageData: makeImageData())

        XCTAssertNil(item.imageFileName, "no file should be referenced while persistence is off")
        XCTAssertEqual(imageFilesOnDisk(), before, "no new file should appear in clipboardDataDirectory")
    }

    /// …and the image is still usable, so previews and re-copying keep working.
    func testImageRemainsReadableFromMemoryWhilePersistenceIsOff() {
        Defaults[.persistClipboardHistory] = false
        let png = makeImageData()

        let item = ClipboardItem(imageData: png)

        XCTAssertEqual(item.getImageData(), png)
    }

    /// With the setting on, the previous behaviour is unchanged.
    func testImageCopyStillWritesAFileWhilePersistenceIsOn() {
        Defaults[.persistClipboardHistory] = true
        let before = imageFilesOnDisk()

        let item = ClipboardItem(imageData: makeImageData())
        defer {
            if let name = item.imageFileName {
                try? FileManager.default.removeItem(
                    at: ClipboardManager.clipboardDataDirectory.appendingPathComponent(name)
                )
            }
        }

        XCTAssertNotNil(item.imageFileName)
        XCTAssertEqual(imageFilesOnDisk().subtracting(before).count, 1)
        XCTAssertEqual(item.getImageData()?.isEmpty, false)
    }

    /// Bytes are dropped once the item they belong to is gone, so the store
    /// stays bounded by the history rather than growing for the session.
    func testInMemoryImagesArePrunedWhenItemsGoAway() {
        Defaults[.persistClipboardHistory] = false
        let item = ClipboardItem(imageData: makeImageData())
        XCTAssertNotNil(item.getImageData())

        ClipboardItem.pruneInMemoryImages(keeping: [])

        XCTAssertNil(item.getImageData(), "bytes for a discarded item should not be retained")
    }

    // MARK: - Stored history

    /// Launching with the setting off must clear history saved by an earlier
    /// session. This runs at startup rather than in the manager's `init`,
    /// because the manager is created lazily and may never be created at all.
    func testLaunchPurgeClearsStoredHistoryWhenDisabled() {
        UserDefaults.standard.set(Data("[]".utf8), forKey: historyKey)
        Defaults[.persistClipboardHistory] = false

        ClipboardManager.purgeStoredHistoryIfPersistenceDisabled()

        XCTAssertNil(UserDefaults.standard.data(forKey: historyKey))
    }

    func testLaunchPurgeLeavesStoredHistoryAloneWhenEnabled() {
        let stored = Data("[]".utf8)
        UserDefaults.standard.set(stored, forKey: historyKey)
        Defaults[.persistClipboardHistory] = true

        ClipboardManager.purgeStoredHistoryIfPersistenceDisabled()

        XCTAssertEqual(UserDefaults.standard.data(forKey: historyKey), stored)
        UserDefaults.standard.removeObject(forKey: historyKey)
    }
}
