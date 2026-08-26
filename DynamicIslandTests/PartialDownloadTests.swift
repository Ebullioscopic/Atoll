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

/// The scan-to-scan path, driven through `DownloadManager` itself rather than
/// through `PartialDownload` alone.
///
/// The rules `PartialDownload` states are only half the feature: the other
/// half is which files each scan hands it, and that is where the awkward
/// cases live -- a download already running when Atoll starts, one that lands
/// while another is still writing, and a destination that was on disk before
/// anything was downloaded onto it.
@MainActor
final class DownloadScanSequenceTests: XCTestCase {
    private let started = Date(timeIntervalSince1970: 1_000_000)
    private var written: Date { started.addingTimeInterval(30) }

    private func makeManager() -> DownloadManager {
        DownloadManager(monitoringDisabledForTesting: true)
    }

    /// Firefox: an empty destination appears first and the bytes go to the
    /// `.part` file beside it, so the destination existing proves nothing and
    /// only its being written does. An empty file has no stamp entry.
    func testFirefoxPlaceholderThenCompletionReportsCompleted() {
        let manager = makeManager()
        manager.processScanForTesting([])                       // first scan: nothing running
        manager.processScanForTesting(["a.zip.part"])           // placeholder + part file
        XCTAssertTrue(manager.isDownloading)
        XCTAssertFalse(manager.isDownloadCompleted)

        // The part file is renamed onto a destination that now holds data.
        manager.processScanForTesting([], stamps: ["a.zip": written])
        XCTAssertTrue(manager.isDownloadCompleted)
    }

    /// A download told to replace a file that is already there starts with a
    /// destination holding data. Cancelling it must not read as a completion.
    func testCancellationOverPreExistingDestinationIsNotCompletion() {
        let manager = makeManager()
        manager.processScanForTesting([], stamps: ["a.zip": started])
        manager.processScanForTesting(["a.zip.crdownload"], stamps: ["a.zip": started])
        XCTAssertTrue(manager.isDownloading)

        // Cancelled: the temporary file is gone and the destination is exactly
        // as old as it was when the download started.
        manager.processScanForTesting([], stamps: ["a.zip": started])
        XCTAssertFalse(manager.isDownloadCompleted)
        XCTAssertFalse(manager.isDownloading)
    }

    /// A download already running when Atoll starts belongs to whoever started
    /// it, and does not get an activity of its own.
    func testDownloadRunningAtLaunchIsIgnored() {
        let manager = makeManager()
        manager.processScanForTesting(["old.zip.crdownload"])   // first scan
        XCTAssertFalse(manager.isDownloading)

        manager.processScanForTesting(["old.zip.crdownload"])   // still writing
        XCTAssertFalse(manager.isDownloading)
    }

    /// ...but once that file is gone the name is free again, so a later
    /// download reusing it is a new download rather than one ignored forever.
    func testNameIsFreeAgainAfterTheIgnoredFileGoes() {
        let manager = makeManager()
        manager.processScanForTesting(["old.zip.crdownload"])
        manager.processScanForTesting([])                       // the old one ends
        XCTAssertFalse(manager.isDownloading)

        manager.processScanForTesting(["old.zip.crdownload"])   // a new download, same name
        XCTAssertTrue(manager.isDownloading)
    }

    /// One download landing while another is still writing cannot be judged at
    /// the scan that sees it go, because there is still active work. It has to
    /// be remembered until the writing stops, or a run whose last download was
    /// cancelled closes the activity with nothing shown for the ones that
    /// finished.
    func testCompletionIsRememberedWhileAnotherDownloadIsStillWriting() {
        let manager = makeManager()
        manager.processScanForTesting([])
        manager.processScanForTesting(["a.zip.crdownload", "b.zip.crdownload"])
        XCTAssertTrue(manager.isDownloading)

        // a finishes; b is still going, so nothing is decided yet.
        manager.processScanForTesting(["b.zip.crdownload"], stamps: ["a.zip": written])
        XCTAssertFalse(manager.isDownloadCompleted)

        // b is cancelled. a still counts.
        manager.processScanForTesting([], stamps: ["a.zip": written])
        XCTAssertTrue(manager.isDownloadCompleted)
    }

    /// The completion animation owns the next couple of seconds, and the
    /// rename that finishes a download is itself a directory event -- so a
    /// scan arrives mid-animation, finds nothing left to have completed, and
    /// must not close the view out from under it.
    func testFollowUpScanDoesNotInterruptTheCompletionAnimation() {
        let manager = makeManager()
        manager.processScanForTesting([])
        manager.processScanForTesting(["a.zip.crdownload"])
        manager.processScanForTesting([], stamps: ["a.zip": written])
        XCTAssertTrue(manager.isDownloadCompleted)

        manager.processScanForTesting([], stamps: ["a.zip": written])
        XCTAssertTrue(manager.isDownloadCompleted, "the animation was cut short")
        XCTAssertTrue(manager.isDownloading, "the activity was closed mid-animation")
    }
}
