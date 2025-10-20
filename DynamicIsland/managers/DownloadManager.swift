//
//  DownloadManager.swift
//  DynamicIsland
//
//  Created by Davide De Lellis on 20/10/25.
//


//
//  DownloadManager.swift
//  DynamicIsland
//
//  Monitors the user's Downloads folder for active downloads and progress.
//  Event-driven monitoring using DispatchSource + Smart polling fallback
//

import Foundation
import AppKit

class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    struct DownloadItem: Identifiable {
        let id = UUID()
        let url: URL
        var progress: Double
        var isCompleted: Bool
    }
    
    @Published var currentDownload: DownloadItem?
    
    private var downloadsFolderURL: URL
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollingTimer: Timer?
    private var lastTempSize: UInt64 = 0
    private var lastKnownSize: UInt64 = 0
    private var lastChangeTime: Date?
    private var stableTicks: Int = 0
    private var expectedFinalSize: UInt64 = 0
    private var downloadStartTime: Date?
    private var currentTempURL: URL?
    private var currentFinalURL: URL?
    
    private override init() {
        downloadsFolderURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        super.init()
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Event-Driven Monitoring
    
    func startMonitoring() {
        let fd = open(downloadsFolderURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("Failed to open Downloads folder for monitoring")
            return
        }
        
        let queue = DispatchQueue(label: "downloads.monitor.queue")
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .link, .rename],
            queue: queue
        )
        
        src.setEventHandler { [weak self] in
            print("Downloads folder changed - checking for active downloads")
            self?.detectActiveDownload()
        }
        
        src.setCancelHandler {
            close(fd)
        }
        
        folderSource = src
        src.resume()
        
        print("Event-driven download monitoring started")
        detectActiveDownload()
    }
    
    func stopMonitoring() {
        folderSource?.cancel()
        folderSource = nil
        stopFileMonitoring()
        stopPollingTimer()
        print("Download monitoring stopped")
    }
    
    // MARK: - File-Specific Event Monitoring
    
    private func startFileMonitoring(for tempURL: URL) {
        stopFileMonitoring()
        
        let pathToMonitor = tempURL.path
        let fd = open(pathToMonitor, O_EVTONLY)
        
        guard fd >= 0 else {
            print("Failed to open file for monitoring: \(tempURL.lastPathComponent)")
            return
        }
        
        let queue = DispatchQueue(label: "downloads.file.monitor.queue")
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: queue
        )
        
        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            print("File changed: \(tempURL.lastPathComponent)")
            self.lastChangeTime = Date()
            self.checkProgressUpdate(tempURL: tempURL)
        }
        
        src.setCancelHandler {
            close(fd)
        }
        
        fileSource = src
        src.resume()
        
        print("File-level event monitoring started for: \(tempURL.lastPathComponent)")
    }
    
    private func stopFileMonitoring() {
        fileSource?.cancel()
        fileSource = nil
    }
    
    // MARK: - Download Detection
    
    private func detectActiveDownload() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: downloadsFolderURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        if let current = currentDownload, !current.isCompleted {
            let tempPossibleNames = [
                current.url.appendingPathExtension("download"),
                current.url.appendingPathExtension("crdownload"),
                current.url.appendingPathExtension("part")
            ]
            
            let tempStillExists = tempPossibleNames.contains { fileManager.fileExists(atPath: $0.path) }
            let finalExists = fileManager.fileExists(atPath: current.url.path)
            
            if !tempStillExists && finalExists {
                print("Event detected completion: temp gone, final exists")
                DispatchQueue.main.async { [weak self] in
                    self?.finishDownload()
                }
                return
            }
        }
        
        if let tempFile = contents.first(where: {
            $0.pathExtension == "download" ||
            $0.pathExtension == "crdownload" ||
            $0.pathExtension == "part"
        }) {
            print("Found temp file: \(tempFile.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.beginTracking(for: tempFile)
            }
            return
        }
        
        if let recentFile = contents
            .filter({ $0.pathExtension != "DS_Store" && $0.pathExtension != "download" && $0.pathExtension != "crdownload" && $0.pathExtension != "part" })
            .sorted(by: {
                let date1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2
            })
            .first,
           let values = try? recentFile.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
           let modDate = values.contentModificationDate,
           abs(modDate.timeIntervalSinceNow) < 5,
           (values.fileSize ?? 0) > 100_000 {
            
            print("Found recently completed file: \(recentFile.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                self?.currentDownload = DownloadItem(url: recentFile, progress: 1.0, isCompleted: true)
                self?.finishDownload()
            }
        }
    }
    
    // MARK: - Progress Tracking
    
    private func beginTracking(for tempURL: URL) {
        let finalURL: URL
        if tempURL.pathExtension == "download" {
            finalURL = tempURL.deletingPathExtension()
        } else {
            finalURL = tempURL.deletingPathExtension()
        }
        
        currentTempURL = tempURL
        currentFinalURL = finalURL
        
        if tempURL.pathExtension == "download" {
            lastTempSize = directorySize(at: tempURL)
        } else if let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey])).flatMap({ $0.fileSize }) {
            lastTempSize = UInt64(size)
        }
        
        lastKnownSize = lastTempSize
        stableTicks = 0
        expectedFinalSize = 0
        downloadStartTime = Date()
        lastChangeTime = Date()
        
        print("Started tracking download: \(finalURL.lastPathComponent)")
        
        DispatchQueue.main.async { [weak self] in
            self?.currentDownload = DownloadItem(url: finalURL, progress: 0.05, isCompleted: false)
        }
        
        DynamicIslandViewCoordinator.shared.toggleSneakPeek(status: true, type: .download, duration: 3600)
        
        startFileMonitoring(for: tempURL)
        startSmartPolling()
    }
    
    private func startSmartPolling() {
        stopPollingTimer()
        
        var tickCount = 0
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            tickCount += 1
            let shouldCheck = (tickCount % 3 == 0) ||
                              (self.lastChangeTime != nil && Date().timeIntervalSince(self.lastChangeTime!) < 10)
            
            if shouldCheck {
                print("Smart polling check (tick \(tickCount))")
                if let tempURL = self.currentTempURL {
                    self.checkProgressUpdate(tempURL: tempURL)
                }
            }
        }
        
        print("Smart polling started (2s interval)")
    }
    
    private func stopPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    private func checkProgressUpdate(tempURL: URL) {
        guard let finalURL = currentFinalURL else { return }
        
        let fileManager = FileManager.default
        
        var tempSize: UInt64 = 0
        var finalSize: UInt64 = 0
        
        let tempExists = fileManager.fileExists(atPath: tempURL.path)
        let finalExists = fileManager.fileExists(atPath: finalURL.path)
        
        if tempExists {
            if tempURL.pathExtension == "download" {
                tempSize = directorySize(at: tempURL)
            } else if let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey])).flatMap({ $0.fileSize }) {
                tempSize = UInt64(size)
            }
        }
        
        if finalExists {
            if let size = (try? finalURL.resourceValues(forKeys: [.fileSizeKey])).flatMap({ $0.fileSize }) {
                finalSize = UInt64(size)
            }
        }
        
        if !tempExists && finalExists && finalSize > 0 {
            print("Download completed: temp file removed, final file exists (\(finalSize) bytes)")
            DispatchQueue.main.async { [weak self] in
                self?.finishDownload()
            }
            return
        }
        
        if !tempExists && finalExists {
            print("Download completed: only final file exists")
            DispatchQueue.main.async { [weak self] in
                self?.finishDownload()
            }
            return
        }
        
        if tempSize > 0 && tempSize == lastKnownSize {
            stableTicks += 1
            
            if stableTicks >= 3 && finalExists {
                print("Download completed: temp stable for \(stableTicks) checks + final exists")
                DispatchQueue.main.async { [weak self] in
                    self?.finishDownload()
                }
                return
            }
        } else {
            stableTicks = 0
        }
        
        if let startTime = downloadStartTime,
           Date().timeIntervalSince(startTime) > 30 &&
           finalExists && finalSize > 0 {
            print("Download completed: timeout reached, final file exists (\(finalSize) bytes)")
            DispatchQueue.main.async { [weak self] in
                self?.finishDownload()
            }
            return
        }
        
        let progressEstimate: Double
        
        if finalSize > 0 && tempSize > 0 {
            let totalSize = finalSize + tempSize
            progressEstimate = min(0.98, Double(finalSize) / Double(totalSize))
            
            if expectedFinalSize == 0 {
                expectedFinalSize = totalSize
            }
            
            print("Progress: \(Int(progressEstimate * 100))% (final: \(finalSize), temp: \(tempSize))")
            
            if progressEstimate > 0.95 && tempSize < (finalSize / 20) {
                stableTicks += 1
                print("Near completion: progress \(Int(progressEstimate * 100))%, small temp remaining")
            }
        } else if finalSize > 0 && tempSize == 0 {
            print("Download completed: only final file, no temp")
            DispatchQueue.main.async { [weak self] in
                self?.finishDownload()
            }
            return
        } else if tempSize > 0 {
            if lastKnownSize > 0 {
                if tempSize > lastKnownSize {
                    let growthRatio = Double(tempSize - lastKnownSize) / Double(lastKnownSize)
                    let currentProgress = currentDownload?.progress ?? 0.05
                    let increment = min(0.15, growthRatio * 0.2)
                    progressEstimate = min(0.98, currentProgress + increment)
                    
                    print("Progress: \(Int(progressEstimate * 100))% (temp growing: \(tempSize))")
                } else {
                    progressEstimate = currentDownload?.progress ?? 0.05
                    print("File stable at \(tempSize) bytes (tick \(stableTicks))")
                }
                
                lastKnownSize = tempSize
            } else {
                progressEstimate = 0.05
                lastKnownSize = tempSize
            }
        } else {
            progressEstimate = currentDownload?.progress ?? 0.05
            print("No files found during update - re-detecting")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.detectActiveDownload()
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.setProgress(progressEstimate)
        }
    }
    
    // MARK: - Helpers
    
    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey])).flatMap({ $0.fileSize }) {
                total += UInt64(size)
            }
        }
        return total
    }
    
    private func setProgress(_ value: Double) {
        guard var item = currentDownload, !item.isCompleted else { return }
        item.progress = max(0.0, min(1.0, value))
        currentDownload = item
    }
    
    private func finishDownload() {
        guard var item = currentDownload else { return }
        
        print("Download finished: \(item.url.lastPathComponent)")
        
        stopFileMonitoring()
        stopPollingTimer()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.objectWillChange.send()
            
            item.progress = 1.0
            item.isCompleted = true
            self.currentDownload = item
            
            print("UI updated: isCompleted = true, progress = 1.0")
            
            DynamicIslandViewCoordinator.shared.toggleSneakPeek(status: true, type: .download, duration: 3.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                print("Clearing download state")
                self.currentDownload = nil
                self.currentTempURL = nil
                self.currentFinalURL = nil
            }
        }
    }
    
    // MARK: - Public Actions
    
    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadsFolderURL)
    }
}
