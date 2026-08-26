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

import Foundation
import SwiftUI
import Observation
import Defaults

/// The half-finished files browsers leave in the Downloads folder, and the
/// finished file each one is going to turn into.
///
/// Every browser names its temporary file after the destination and adds an
/// extension: Chromium writes `archive.zip.crdownload`, Safari an
/// `archive.zip.download` bundle, Firefox `archive.zip.part`, and Opera --
/// Chromium underneath, but with its own name for this -- `archive.zip.opdownload`.
/// Stripping that extension therefore names the file the download is aiming at,
/// whichever browser produced it.
enum PartialDownload {
    /// Extensions that mark a file as still being written, lowercased.
    static let extensions: Set<String> = ["crdownload", "download", "opdownload", "part"]

    /// Whether `name` is a download in progress rather than a finished file.
    static func isInProgress(_ name: String) -> Bool {
        extensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// The name `name` takes once the browser is finished with it.
    static func destination(of name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    /// Of the temporary files that have just vanished, the ones that finished —
    /// the rest were cancelled.
    ///
    /// A download is finished once its destination has been *written*, which is
    /// not the same as the destination being there. Two cases make the
    /// difference matter. Firefox creates the destination up front as an empty
    /// placeholder and writes the bytes to the `.part` file beside it, so mere
    /// existence proves nothing — holding data is the test, and only non-empty
    /// files get a stamp. And a download told to replace a file that is already
    /// there starts with a destination that holds data before a single byte
    /// arrives, so the stamp has to have *changed* since the temporary file
    /// appeared; otherwise cancelling one reads as a completion.
    ///
    /// - Parameters:
    ///   - stamps: modification dates of the non-empty files on disk now.
    ///   - stampsWhenStarted: the same, captured for each destination when its
    ///     temporary file first appeared. A missing entry means there was
    ///     nothing there, or nothing with anything in it.
    static func completed(
        among disappearedFiles: Set<String>,
        stamps: [String: Date],
        stampsWhenStarted: [String: Date]
    ) -> Set<String> {
        disappearedFiles.filter { name in
            let target = destination(of: name)
            guard let now = stamps[target] else { return false }
            guard let before = stampsWhenStarted[target] else { return true }
            // Later, not merely different. A destination that came out older
            // than it was when the download started was not written by it --
            // something restored or copied an earlier file over the name.
            return now > before
        }
    }
}

@Observable
@MainActor
class DownloadManager {
    static let shared = DownloadManager()
    
    private(set) var isDownloading: Bool = false
    private(set) var isDownloadCompleted: Bool = false
    
    private let coordinator = DynamicIslandViewCoordinator.shared
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.dynamicisland.downloads.monitor", qos: .utility)
    private var completionTimer: Timer?
    private var hasPerformedInitialScan: Bool = false
    private var previousInProgressFiles: Set<String> = []
    private var ignoredFiles: Set<String> = []
    /// Temporary files that have gone since the live activity appeared, held
    /// until nothing is being written any more. A download that lands while
    /// another is still going cannot be judged at the scan that sees it go —
    /// there is still active work — and dropping it there meant a run whose
    /// last download was cancelled closed the activity outright, with nothing
    /// shown for the ones that had finished.
    private var vanishedSinceActive: Set<String> = []
    /// What each in-flight download's destination looked like when its
    /// temporary file appeared, so a destination that was already on disk is
    /// not mistaken for one this download wrote.
    private var destinationStampsWhenStarted: [String: Date] = [:]
    
    private var downloadsDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    init() {
        requestDownloadsPermissionIfNeeded()
        startMonitoringIfNeeded()
        
        Defaults.publisher(.enableDownloadListener)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.startMonitoringIfNeeded()
                }
            }
    }
    
    private func startMonitoringIfNeeded() {
        if Defaults[.enableDownloadListener] {
            startMonitoring()
        } else {
            stopMonitoring()
            // Not updateDownloadingState: stopMonitoring has already cleared
            // isDownloading, which is the flag that call checks before doing
            // anything, so switching the listener off mid-download left the
            // live activity on screen with nothing left to close it.
            closeDownloadViewImmediately()
        }
    }
    
    private func startMonitoring() {
        guard source == nil, let downloadsDirectory else { return }
        
        hasPerformedInitialScan = false
        previousInProgressFiles.removeAll()
        ignoredFiles.removeAll()
        vanishedSinceActive.removeAll()
        destinationStampsWhenStarted.removeAll()
        isDownloading = false

        let path = downloadsDirectory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: queue
        )
        
        src.setEventHandler { [weak self] in
            self?.scanDownloadsDirectory()
        }
        
        src.setCancelHandler {
            close(fd)
        }
        
        source = src
        src.resume()
        
        scanDownloadsDirectory()
    }
    
    private func stopMonitoring() {
        source?.cancel()
        source = nil
        
        hasPerformedInitialScan = false
        previousInProgressFiles.removeAll()
        ignoredFiles.removeAll()
        vanishedSinceActive.removeAll()
        destinationStampsWhenStarted.removeAll()
        isDownloading = false
    }
    
    private func scanDownloadsDirectory() {
        guard let downloadsDirectory else { return }
        
        let inProgressFiles: Set<String>
        var stamps: [String: Date] = [:]

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )

            inProgressFiles = Set(contents
                .map { $0.lastPathComponent }
                .filter { PartialDownload.isInProgress($0) }
            )

            for url in contents {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard (values?.fileSize ?? 0) > 0, let modified = values?.contentModificationDate else { continue }
                stamps[url.lastPathComponent] = modified
            }

        } catch {
            return
        }

        let resolvedStamps = stamps
        Task { @MainActor in
            self.processDownloadFiles(inProgressFiles, stamps: resolvedStamps)
        }
    }
    
    private func processDownloadFiles(_ inProgressFiles: Set<String>, stamps: [String: Date]) {

        if !hasPerformedInitialScan {
            hasPerformedInitialScan = true
            previousInProgressFiles = inProgressFiles
            ignoredFiles = inProgressFiles
            isDownloading = false
            return
        }

        let disappearedFiles = previousInProgressFiles.subtracting(inProgressFiles)
        let appearedFiles = inProgressFiles.subtracting(previousInProgressFiles)
        previousInProgressFiles = inProgressFiles

        // Captured the moment a download starts writing, and only then: taking
        // it later would record what this download had already put there.
        for name in appearedFiles {
            let target = PartialDownload.destination(of: name)
            destinationStampsWhenStarted[target] = stamps[target]
        }

        // Judged against the ignore list as it stands, before the expiry below.
        vanishedSinceActive.formUnion(disappearedFiles.subtracting(ignoredFiles))

        // A partial file present at launch is ignored by name, so a download
        // already running when the app starts does not claim an activity of its
        // own. Once that file is gone the name is free again — a later download
        // that happens to reuse it is a new download, and was otherwise ignored
        // for the life of the process.
        ignoredFiles.subtract(disappearedFiles)

        let activeFiles = inProgressFiles.subtracting(ignoredFiles)

        if !activeFiles.isEmpty {
            // Covers both a download appearing and one still writing: the state
            // update is a no-op once the live activity is already showing.
            updateDownloadingState(isActive: true)
            return
        }

        // completion logic
        guard isDownloading else {
            vanishedSinceActive.removeAll()
            destinationStampsWhenStarted.removeAll()
            return
        }

        // The completion animation owns the next couple of seconds, and a
        // directory event during them is likely rather than hypothetical --
        // the rename that finishes a download is itself one. Such a scan finds
        // nothing left to have completed, and would close the view mid-animation.
        guard !isDownloadCompleted else {
            vanishedSinceActive.removeAll()
            return
        }

        // Nothing is being written any more, so the downloads that were running
        // have either landed on their destination or been abandoned. Only a
        // finished one earns the completion animation; the destination never
        // appears as a download of its own, because a file that is not still
        // being written is not a partial download.
        let completedFiles = PartialDownload.completed(
            among: vanishedSinceActive,
            stamps: stamps,
            stampsWhenStarted: destinationStampsWhenStarted
        )
        vanishedSinceActive.removeAll()
        destinationStampsWhenStarted.removeAll()

        if completedFiles.isEmpty {
            closeDownloadViewImmediately()
        } else {
            updateDownloadingState(isActive: false)
        }
    }
    
#if DEBUG
    /// A manager that watches nothing, for tests.
    ///
    /// The scan-to-scan bookkeeping is the part worth testing and the part
    /// hardest to reach: it is driven by a directory watcher on the real
    /// Downloads folder, so exercising it any other way means creating files
    /// on the machine running the tests and racing the file system for them.
    /// This builds the same object with no watcher attached, so scans can be
    /// handed to it directly.
    init(monitoringDisabledForTesting: Bool) {
        precondition(monitoringDisabledForTesting)
    }

    /// One scan, in the shape the directory watcher delivers them.
    ///
    /// - Parameters:
    ///   - inProgressFiles: the partial-download files in the folder now.
    ///   - stamps: modification dates of the **non-empty** files in the folder
    ///     now. An empty file has no entry, which is how Firefox's placeholder
    ///     destination is told apart from one that has been written.
    func processScanForTesting(_ inProgressFiles: Set<String>, stamps: [String: Date] = [:]) {
        processDownloadFiles(inProgressFiles, stamps: stamps)
    }
#endif

    private func requestDownloadsPermissionIfNeeded() {
        guard let downloadsDirectory else { return }
        _ = try? FileManager.default.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil)
    }
    
    private func updateDownloadingState(isActive: Bool) {
        completionTimer?.invalidate()
        completionTimer = nil
        
        if isActive {
            isDownloadCompleted = false
            
            if !isDownloading {
                withAnimation(.smooth) {
                    isDownloading = true
                }
                coordinator.toggleExpandingView(
                    status: true,
                    type: .download,
                    value: 0,
                    browser: .chromium
                )
            }
            
        } else {
            if isDownloading {
                withAnimation(.smooth) {
                    isDownloadCompleted = true
                }
                
                completionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.closeDownloadView()
                    }
                }
            }
        }
    }
    
    private func closeDownloadView() {
        withAnimation(.smooth) {
            isDownloading = false
            isDownloadCompleted = false
        }
        
        coordinator.toggleExpandingView(
            status: false,
            type: .download,
            value: 0,
            browser: .chromium
        )
    }
    
    private func closeDownloadViewImmediately() {
        completionTimer?.invalidate()
        completionTimer = nil
        
        withAnimation(.smooth) {
            isDownloading = false
            isDownloadCompleted = false
        }
        
        coordinator.toggleExpandingView(
            status: false,
            type: .download,
            value: 0,
            browser: .chromium
        )
    }
}
