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

/// The download live activity is driven purely by what the Downloads folder
/// looks like from one scan to the next, so the browsers' naming conventions
/// are what the whole feature rests on.
final class PartialDownloadTests: XCTestCase {
    /// Every file on disk is stamped with the same arbitrary date unless a test
    /// cares about the difference, which keeps the cases about the rule.
    private let arbitrary = Date(timeIntervalSince1970: 1_000_000)

    private func stamps(_ names: Set<String>) -> [String: Date] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, arbitrary) })
    }

    /// Each browser marks work in progress with its own extension.
    func testRecognisesEveryBrowsersTemporaryFile() {
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.crdownload"))
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.download"))
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.part"))
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.opdownload"))
    }

    /// Extensions come off disks in whatever case the browser felt like.
    func testRecognisesTemporaryFilesRegardlessOfCase() {
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.CRDownload"))
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.PART"))
        XCTAssertTrue(PartialDownload.isInProgress("archive.zip.OPDownload"))
    }

    /// A finished file is not a download, however much it looks like one.
    func testFinishedFilesAreNotInProgress() {
        XCTAssertFalse(PartialDownload.isInProgress("archive.zip"))
        XCTAssertFalse(PartialDownload.isInProgress("notes.partial"))
        XCTAssertFalse(PartialDownload.isInProgress("no-extension"))
    }

    /// Every browser appends to the destination name, so one rule strips it.
    func testDestinationIsTheNameWithoutTheTemporaryExtension() {
        XCTAssertEqual(PartialDownload.destination(of: "archive.zip.crdownload"), "archive.zip")
        XCTAssertEqual(PartialDownload.destination(of: "archive.zip.download"), "archive.zip")
        XCTAssertEqual(PartialDownload.destination(of: "archive.zip.part"), "archive.zip")
        XCTAssertEqual(PartialDownload.destination(of: "archive.zip.opdownload"), "archive.zip")
        XCTAssertEqual(PartialDownload.destination(of: "report.2026.01.pdf.part"), "report.2026.01.pdf")
    }

    /// Chromium renames its `.crdownload` onto the destination, which is the
    /// first time that name exists at all.
    func testChromiumDownloadCompletesWhenTheDestinationAppears() {
        XCTAssertEqual(
            PartialDownload.completed(among: ["archive.zip.crdownload"], stamps: stamps(["archive.zip"]), stampsWhenStarted: [:]),
            ["archive.zip.crdownload"]
        )
    }

    /// Firefox writes into `archive.zip.part` next to a placeholder it created
    /// as `archive.zip` before the transfer started, then renames the part file
    /// over it. Only the rename fills the destination with data.
    func testFirefoxDownloadCompletesOnlyOnceTheDestinationHoldsData() {
        // Mid-download: the part file is gone from this set only because the
        // caller passes what disappeared, and the placeholder is still empty.
        XCTAssertTrue(
            PartialDownload.completed(among: ["archive.zip.part"], stamps: stamps([]), stampsWhenStarted: [:]).isEmpty,
            "an empty placeholder must not be mistaken for a finished download"
        )

        XCTAssertEqual(
            PartialDownload.completed(among: ["archive.zip.part"], stamps: stamps(["archive.zip"]), stampsWhenStarted: [:]),
            ["archive.zip.part"]
        )
    }

    /// Cancelling removes the part file and the placeholder both, and a scan
    /// landing between the two removals still sees an empty placeholder.
    func testCancelledFirefoxDownloadNeverCounts() {
        for remaining in [Set<String>(), ["unrelated.dmg"]] {
            XCTAssertTrue(
                PartialDownload.completed(among: ["archive.zip.part"], stamps: stamps(remaining), stampsWhenStarted: [:]).isEmpty
            )
        }
    }

    /// Two downloads ending at once are judged one at a time.
    func testFinishedAndCancelledDownloadsAreToldApart() {
        XCTAssertEqual(
            PartialDownload.completed(
                among: ["archive.zip.part", "movie.mp4.crdownload"],
                stamps: stamps(["archive.zip"]),
                stampsWhenStarted: [:]
            ),
            ["archive.zip.part"]
        )
    }

    /// The destination of a Firefox download sits in the Downloads folder for
    /// the whole transfer. It must never be picked up as a download of its own,
    /// or a single download would drive two live activities.
    func testTheDestinationIsNeverItselfADownload() {
        XCTAssertFalse(PartialDownload.isInProgress(PartialDownload.destination(of: "archive.zip.part")))
    }

    /// One download landing while another is still writing must survive to the
    /// scan that decides the outcome. The set is accumulated by the manager;
    /// what matters here is that a mixed batch is judged per file, not as a
    /// whole — a later cancellation must not disown an earlier completion.
    func testCompletionSurvivesACancellationInTheSameBatch() {
        let vanished: Set<String> = ["landed.zip.part", "abandoned.dmg.part"]
        let onDisk: Set<String> = ["landed.zip"]

        XCTAssertEqual(
            PartialDownload.completed(among: vanished, stamps: stamps(onDisk), stampsWhenStarted: [:]),
            ["landed.zip.part"]
        )
    }

    /// And the reverse: nothing on disk means nothing finished, however many
    /// files went at once.
    func testABatchWithNothingOnDiskCompletesNothing() {
        let vanished: Set<String> = ["one.zip.part", "two.dmg.crdownload"]

        XCTAssertTrue(
            PartialDownload.completed(among: vanished, stamps: stamps(["unrelated.txt"]), stampsWhenStarted: [:]).isEmpty
        )
    }

    /// A download told to replace a file that is already there starts with a
    /// destination full of the *old* file's bytes. Cancelling it must not read
    /// as a completion just because something is sitting at the target name.
    func testReplacingCancelledLeavesTheOldFileAlone() {
        let existing = stamps(["archive.zip"])

        XCTAssertTrue(
            PartialDownload.completed(
                among: ["archive.zip.crdownload"],
                stamps: existing,
                stampsWhenStarted: existing
            ).isEmpty
        )
    }

    /// The same replace, but finished: the rename gives the destination a new
    /// modification date, which is what separates it from the case above.
    func testReplacingCompletedIsACompletion() {
        let before = stamps(["archive.zip"])
        let after = ["archive.zip": arbitrary.addingTimeInterval(30)]

        XCTAssertEqual(
            PartialDownload.completed(
                among: ["archive.zip.crdownload"],
                stamps: after,
                stampsWhenStarted: before
            ),
            ["archive.zip.crdownload"]
        )
    }

    /// Later, not merely different. A destination that comes out older than it
    /// was when the download started was not written by that download.
    func testAnOlderDestinationIsNotACompletion() {
        let before = ["archive.zip": arbitrary]
        let after = ["archive.zip": arbitrary.addingTimeInterval(-60)]

        XCTAssertTrue(
            PartialDownload.completed(
                among: ["archive.zip.crdownload"],
                stamps: after,
                stampsWhenStarted: before
            ).isEmpty
        )
    }
}
