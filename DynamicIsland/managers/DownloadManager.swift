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
    private var initialCrDownloadFiles: Set<String> = []
    private var previousAllFiles: Set<String> = []
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
        initialCrDownloadFiles.removeAll()
        previousAllFiles.removeAll()
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
        initialCrDownloadFiles.removeAll()
        ignoredFiles.removeAll()
        isDownloading = false
    }
    
    private func scanDownloadsDirectory() {
        guard let downloadsDirectory else { return }
        
        let crDownloadFiles: Set<String>
        let allFiles: Set<String>
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: [.creationDateKey]
            )
            
            crDownloadFiles = Set(contents
                .filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "crdownload" || ext == "download" || ext == "fdmdownload"
                }
                .map { $0.lastPathComponent }
            )
            
            allFiles = Set(contents.map { $0.lastPathComponent })
            
        } catch {
            return
        }
        
        Task { @MainActor in
            self.processDownloadFiles(crDownloadFiles, allFiles: allFiles)
        }
    }
    
    private func processDownloadFiles(_ crDownloadFiles: Set<String>, allFiles: Set<String>) {
        
        if !hasPerformedInitialScan {
            hasPerformedInitialScan = true
            initialCrDownloadFiles = crDownloadFiles
            previousAllFiles = allFiles
            ignoredFiles = crDownloadFiles
            isDownloading = false
            return
        }
        
        let newFiles = crDownloadFiles.subtracting(initialCrDownloadFiles)
        let disappearedFiles = initialCrDownloadFiles.subtracting(crDownloadFiles)
        let newRegularFiles = allFiles.subtracting(previousAllFiles).subtracting(crDownloadFiles)
        
        initialCrDownloadFiles = crDownloadFiles
        previousAllFiles = allFiles
        
        let activeFiles = crDownloadFiles.subtracting(ignoredFiles)
        let hasActiveDownloads = !activeFiles.isEmpty
        
        if !newFiles.isEmpty {
            let newActiveFiles = newFiles.subtracting(ignoredFiles)
            if !newActiveFiles.isEmpty {
                if !isDownloading {
                    updateDownloadingState(isActive: true)
                }
            }
        }
        
        // completion logic
        if isDownloading {
            if !hasActiveDownloads {
                if !newRegularFiles.isEmpty || disappearedFiles.isEmpty {
                    
                    if !isDownloadCompleted {
                        updateDownloadingState(isActive: false)
                    }
                    
                } else {
                    closeDownloadViewImmediately()
                }
                
            }
            
        } else if hasActiveDownloads {
            updateDownloadingState(isActive: true)
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
