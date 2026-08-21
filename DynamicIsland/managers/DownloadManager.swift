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
/// `archive.zip.download` bundle, Firefox `archive.zip.part`. Stripping that
/// extension therefore names the file the download is aiming at, whichever
/// browser produced it.
enum PartialDownload {
    /// Extensions that mark a file as still being written, lowercased.
    static let extensions: Set<String> = ["crdownload", "download", "part"]

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
    /// A download is only finished once its destination holds data. Firefox
    /// creates the destination up front as an empty placeholder and writes the
    /// bytes to the `.part` file beside it, so mere existence proves nothing:
    /// cancelling removes the `.part` file first and the placeholder a moment
    /// later, and a scan landing in between would read a cancellation as a
    /// completion.
    static func completed(
        among disappearedFiles: Set<String>,
        nonEmptyFiles: Set<String>
    ) -> Set<String> {
        disappearedFiles.filter { nonEmptyFiles.contains(destination(of: $0)) }
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
            updateDownloadingState(isActive: false)
        }
    }
    
    private func startMonitoring() {
        guard source == nil, let downloadsDirectory else { return }
        
        hasPerformedInitialScan = false
        previousInProgressFiles.removeAll()
        ignoredFiles.removeAll()
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
        isDownloading = false
    }
    
    private func scanDownloadsDirectory() {
        guard let downloadsDirectory else { return }
        
        let inProgressFiles: Set<String>
        let nonEmptyFiles: Set<String>

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )

            inProgressFiles = Set(contents
                .map { $0.lastPathComponent }
                .filter { PartialDownload.isInProgress($0) }
            )

            nonEmptyFiles = Set(contents
                .filter { url in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    return size > 0
                }
                .map { $0.lastPathComponent }
            )

        } catch {
            return
        }

        Task { @MainActor in
            self.processDownloadFiles(inProgressFiles, nonEmptyFiles: nonEmptyFiles)
        }
    }
    
    private func processDownloadFiles(_ inProgressFiles: Set<String>, nonEmptyFiles: Set<String>) {

        if !hasPerformedInitialScan {
            hasPerformedInitialScan = true
            previousInProgressFiles = inProgressFiles
            ignoredFiles = inProgressFiles
            isDownloading = false
            return
        }

        let disappearedFiles = previousInProgressFiles.subtracting(inProgressFiles)
        previousInProgressFiles = inProgressFiles

        let activeFiles = inProgressFiles.subtracting(ignoredFiles)
        let hasActiveDownloads = !activeFiles.isEmpty

        if hasActiveDownloads {
            // Covers both a download appearing and one still writing: the state
            // update is a no-op once the live activity is already showing.
            updateDownloadingState(isActive: true)
            return
        }

        // completion logic
        guard isDownloading else { return }

        // Nothing is being written any more, so the downloads that were still
        // running have either landed on their destination or been abandoned.
        // Only a finished one earns the completion animation; the destination
        // never appears as a download of its own, because a file that is not
        // still being written is not a partial download.
        let completedFiles = PartialDownload.completed(
            among: disappearedFiles.subtracting(ignoredFiles),
            nonEmptyFiles: nonEmptyFiles
        )

        if completedFiles.isEmpty {
            closeDownloadViewImmediately()
        } else if !isDownloadCompleted {
            updateDownloadingState(isActive: false)
        }
    }
    
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
