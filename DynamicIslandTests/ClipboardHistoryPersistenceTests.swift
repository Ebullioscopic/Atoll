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

import AppKit
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
    private let pinnedKey = "ClipboardPinnedItems"
    private var originalSetting = true
    private var originalHistory: Data?
    private var originalPinned: Data?
    private var temporaryDirectory: URL!

    /// These tests turn persistence off, and turning it off deletes every
    /// unpinned image file in the clipboard data directory. Pointed at the
    /// real one, running the suite deletes the clipboard images of whoever ran
    /// it, and leaves the stored history and pinned lists as the last test
    /// wrote them. So the directory is a temporary one for the duration, and
    /// both stored lists are put back afterwards.
    override func setUp() {
        super.setUp()
        originalSetting = Defaults[.persistClipboardHistory]
        originalHistory = UserDefaults.standard.data(forKey: historyKey)
        originalPinned = UserDefaults.standard.data(forKey: pinnedKey)

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtollClipboardTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: temporaryDirectory, withIntermediateDirectories: true
        )
        ClipboardManager.directoryOverride = temporaryDirectory
    }

    override func tearDown() {
        ClipboardManager.directoryOverride = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil

        Defaults[.persistClipboardHistory] = originalSetting
        restore(originalHistory, forKey: historyKey)
        restore(originalPinned, forKey: pinnedKey)
        super.tearDown()
    }

    private func restore(_ data: Data?, forKey key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
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

    // MARK: - Transitions

    /// Turning persistence off deletes the files behind history images. The
    /// bytes have to be taken into memory first, or the entries still on
    /// screen lose their picture the moment the setting flips.
    func testImageStaysReadableAfterDisablingPersistence() {
        let manager = ClipboardManager.shared
        let existingHistory = manager.clipboardHistory
        defer { manager.clipboardHistory = existingHistory }

        Defaults[.persistClipboardHistory] = true
        let png = makeImageData()
        let item = ClipboardItem(imageData: png)
        XCTAssertNotNil(item.imageFileName, "expected a file-backed image to start from")
        manager.clipboardHistory = [item]

        Defaults[.persistClipboardHistory] = false
        // The observer runs on the Defaults publisher; give it the turn it needs.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(
            manager.clipboardHistory.first?.getImageData(),
            png,
            "the image should still render and re-copy after the files are deleted"
        )
    }

    /// Turning persistence back on has to give session-only images a file, or
    /// the restart the user just opted into restores entries with no picture.
    func testSessionOnlyImageGainsAFileWhenPersistenceIsEnabled() {
        let manager = ClipboardManager.shared
        let existingHistory = manager.clipboardHistory
        defer { manager.clipboardHistory = existingHistory }

        Defaults[.persistClipboardHistory] = false
        let png = makeImageData()
        let item = ClipboardItem(imageData: png)
        XCTAssertNil(item.imageFileName, "expected a session-only image to start from")
        manager.clipboardHistory = [item]

        Defaults[.persistClipboardHistory] = true
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let name = manager.clipboardHistory.first?.imageFileName else {
            return XCTFail("the image should have been given a file")
        }
        let url = ClipboardManager.clipboardDataDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try? Data(contentsOf: url), png)
    }

    /// Pinning is a request to keep one thing. While history is not being
    /// saved an image has no file behind it, so the pinned record named a file
    /// that was never written and a restart restored a pinned entry with no
    /// picture in it.
    func testPinningAnImageWhileHistoryIsNotSavedGivesItAFile() {
        let manager = ClipboardManager.shared
        let existingHistory = manager.clipboardHistory
        let existingPinned = manager.pinnedItems
        defer {
            manager.clipboardHistory = existingHistory
            manager.pinnedItems = existingPinned
        }

        Defaults[.persistClipboardHistory] = false
        let png = makeImageData()
        let item = ClipboardItem(imageData: png)
        XCTAssertNil(item.imageFileName, "expected a session-only image to start from")

        manager.pinnedItems = []
        manager.pinItem(item)

        guard let name = manager.pinnedItems.first?.imageFileName else {
            return XCTFail("a pinned image should have been given a file")
        }
        let url = ClipboardManager.clipboardDataDirectory.appendingPathComponent(name)
        XCTAssertEqual(try? Data(contentsOf: url), png, "the pinned image should survive a restart")
    }

    /// The rest of the session-only history is not persisted by pinning one
    /// item — only the thing that was pinned.
    func testPinningDoesNotPersistTheRestOfTheSessionOnlyHistory() {
        let manager = ClipboardManager.shared
        let existingHistory = manager.clipboardHistory
        let existingPinned = manager.pinnedItems
        defer {
            manager.clipboardHistory = existingHistory
            manager.pinnedItems = existingPinned
        }

        Defaults[.persistClipboardHistory] = false
        let pinned = ClipboardItem(imageData: makeImageData())
        let other = ClipboardItem(imageData: makeImageData())
        manager.clipboardHistory = [pinned, other]
        manager.pinnedItems = []

        manager.pinItem(pinned)

        XCTAssertEqual(imageFilesOnDisk().count, 1, "only the pinned image should have a file")
        XCTAssertNil(
            manager.clipboardHistory.first(where: { $0.id == other.id })?.imageFileName,
            "the unpinned image should still be memory-only"
        )
    }

    /// The launch purge took the stored list but left the pictures it referred
    /// to sitting in the data directory — and because the manager is lazy,
    /// nothing else deleted them either if the panel was never opened.
    func testLaunchPurgeDeletesUnpinnedImageFilesButKeepsPinnedOnes() {
        let manager = ClipboardManager.shared
        let existingPinned = manager.pinnedItems
        defer { manager.pinnedItems = existingPinned }

        Defaults[.persistClipboardHistory] = true
        let pinnedItem = ClipboardItem(imageData: makeImageData())
        let looseItem = ClipboardItem(imageData: makeImageData())
        guard let pinnedName = pinnedItem.imageFileName,
              let looseName = looseItem.imageFileName else {
            return XCTFail("expected both images to be file-backed")
        }
        manager.pinnedItems = [pinnedItem]
        manager.savePinnedItemsToDefaults()

        Defaults[.persistClipboardHistory] = false
        ClipboardManager.purgeStoredHistoryIfPersistenceDisabled()

        let remaining = imageFilesOnDisk()
        XCTAssertTrue(remaining.contains(pinnedName), "a pinned image was asked to be kept")
        XCTAssertFalse(remaining.contains(looseName), "an unpinned image should not survive the purge")
        XCTAssertNil(UserDefaults.standard.data(forKey: historyKey))
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

    // MARK: - Pinned items

    /// Clearing favorites used to empty the array and save, leaving the PNG
    /// behind every pinned image orphaned in `clipboardDataDirectory`.
    func testClearingPinnedItemsDeletesTheirImageFiles() {
        Defaults[.persistClipboardHistory] = true
        let manager = ClipboardManager.shared
        let existingPins = manager.pinnedItems

        let item = ClipboardItem(imageData: makeImageData())
        guard let fileName = item.imageFileName else {
            return XCTFail("expected an image file while persistence is on")
        }
        let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        manager.pinnedItems = [item]
        manager.clearPinnedItems()

        XCTAssertTrue(manager.pinnedItems.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "the image behind a cleared favorite should not survive"
        )

        manager.pinnedItems = existingPins
        manager.savePinnedItemsToDefaults()
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
