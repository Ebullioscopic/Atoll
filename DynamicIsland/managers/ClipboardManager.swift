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
import SwiftUI
import Combine
import Foundation
import UniformTypeIdentifiers
import Defaults

// Clipboard item data structure
struct ClipboardItem: Identifiable, Codable {
    let id = UUID()
    let type: ClipboardItemType
    let timestamp: Date
    let preview: String
    var isPinned: Bool = false
    
    /// Image bytes for items captured while history persistence is off.
    ///
    /// Held here rather than written to `clipboardDataDirectory`, because the
    /// setting promises nothing reaches disk — and a PNG of whatever you copied
    /// is the most sensitive thing the clipboard handles. Keyed by item id and
    /// pruned as items leave, so it stays bounded by the history size.
    private static var inMemoryImages: [UUID: Data] = [:]
    private static let inMemoryImagesLock = NSLock()

    static func pruneInMemoryImages(keeping ids: Set<UUID>) {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        inMemoryImages = inMemoryImages.filter { ids.contains($0.key) }
    }

    static func storeInMemoryImage(_ data: Data, for id: UUID) {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        inMemoryImages[id] = data
    }

    static func inMemoryImage(for id: UUID) -> Data? {
        inMemoryImagesLock.lock()
        defer { inMemoryImagesLock.unlock() }
        return inMemoryImages[id]
    }

    // Store different types of data - avoid large binary data in UserDefaults
    let stringData: String?
    var imageFileName: String? // Store filename instead of data
    let fileURLs: [String]?
    let rtfData: Data? // RTF is typically small, so we can keep this
    
    init(stringData: String, type: ClipboardItemType) {
        self.stringData = stringData
        self.imageFileName = nil
        self.fileURLs = nil
        self.rtfData = nil
        self.type = type
        self.timestamp = Date()
        self.preview = ClipboardItem.generatePreview(stringData: stringData, type: type)
    }
    
    init(imageData: Data) {
        self.stringData = nil
        self.fileURLs = nil
        self.rtfData = nil
        self.type = .image
        self.timestamp = Date()
        
        let sizeDescription = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)

        guard Defaults[.persistClipboardHistory] else {
            // Session-only: keep the bytes in memory so the image never lands
            // in clipboardDataDirectory.
            self.imageFileName = nil
            self.preview = "Image (\(sizeDescription))"
            ClipboardItem.storeInMemoryImage(imageData, for: id)
            return
        }

        // Save image data to temporary file instead of storing in UserDefaults
        let fileName = "clipboard_image_\(UUID().uuidString).png"
        let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            self.imageFileName = fileName
            self.preview = "Image (\(sizeDescription))"
        } catch {
            print("Failed to save image data: \(error)")
            self.imageFileName = nil
            self.preview = "Image (failed to save)"
        }
    }
    
    init(fileURLs: [String]) {
        self.stringData = nil
        self.imageFileName = nil
        self.fileURLs = fileURLs
        self.rtfData = nil
        self.type = .file
        self.timestamp = Date()
        
        if fileURLs.count == 1, let url = URL(string: fileURLs.first!) {
            self.preview = url.lastPathComponent
        } else {
            self.preview = "\(fileURLs.count) files"
        }
    }
    
    init(rtfData: Data, plainText: String) {
        // RTF data is typically small, so we can keep it in UserDefaults
        self.stringData = plainText
        self.imageFileName = nil
        self.fileURLs = nil
        self.rtfData = rtfData.count > 100000 ? nil : rtfData // Skip very large RTF files
        self.type = .rtf
        self.timestamp = Date()
        self.preview = String(plainText.prefix(50))
    }
    
    // Helper to get image data from memory or file
    func getImageData() -> Data? {
        if let inMemory = ClipboardItem.inMemoryImage(for: id) { return inMemory }
        guard let fileName = imageFileName else { return nil }
        let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
        return try? Data(contentsOf: fileURL)
    }
    
    // Helper to check if this item has the same content as another
    func isSameContent(as other: ClipboardItem) -> Bool {
        return stringData == other.stringData &&
               imageFileName == other.imageFileName &&
               fileURLs == other.fileURLs &&
               type == other.type
    }
    
    static func generatePreview(stringData: String, type: ClipboardItemType) -> String {
        switch type {
        case .text:
            return String(stringData.prefix(50))
        case .url:
            if let url = URL(string: stringData) {
                return url.lastPathComponent.isEmpty ? url.host ?? stringData : url.lastPathComponent
            }
            return String(stringData.prefix(50))
        case .file:
            if let url = URL(string: stringData) {
                return url.lastPathComponent
            }
            return "File"
        case .image:
            return "Image"
        case .rtf:
            return String(stringData.prefix(50))
        case .unknown:
            return String(stringData.prefix(50))
        }
    }
}

enum ClipboardItemType: String, CaseIterable, Codable {
    case text = "text"
    case url = "url"
    case file = "file"
    case image = "image"
    case rtf = "rtf"
    case unknown = "unknown"
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .file: return "doc"
        case .image: return "photo"
        case .rtf: return "doc.richtext"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return String(localized: "Text")
        case .url: return String(localized: "URL")
        case .file: return String(localized: "File")
        case .image: return String(localized: "Image")
        case .rtf: return String(localized: "Rich Text")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var clipboardHistory: [ClipboardItem] = []
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var isMonitoring: Bool = false
    @Published private(set) var lastCopiedItemDate: Date?
    /// True while a clipboard item is being dragged out; keeps the notch open
    /// (see `shouldPreventAutoClose`). SwiftUI `.onDrag` has no drag-end callback,
    /// so a bounded timeout releases it in case a drop is never observed.
    @Published var isDraggingItem: Bool = false
    private var dragResetWork: DispatchWorkItem?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var persistenceCancellable: AnyCancellable?
    
    // Use configurable history size from settings
    private var maxHistoryItems: Int {
        return Defaults[.clipboardHistorySize]
    }
    
    // Computed properties for filtered lists
    var regularHistory: [ClipboardItem] {
        clipboardHistory.filter { !$0.isPinned }
    }
    
    var pinnedHistory: [ClipboardItem] {
        pinnedItems
    }
    
    // Directory for storing clipboard data files
    static var clipboardDataDirectory: URL { directoryOverride ?? defaultDataDirectory }

    /// Where the tests point this instead of the user's own Documents folder.
    ///
    /// The transition tests turn persistence off, which deletes every unpinned
    /// image file in this directory -- so with no override, running the suite
    /// deletes the clipboard images of whoever ran it.
    static var directoryOverride: URL?

    private static let defaultDataDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let clipboardDir = documentsPath.appendingPathComponent("ClipboardData")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: clipboardDir, withIntermediateDirectories: true)
        
        return clipboardDir
    }()
    
    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadHistoryFromDefaults()
        cleanupOldFiles()
        observeHistoryPersistence()
    }

    /// Turning persistence off has to erase what is already on disk, otherwise
    /// the setting would only stop *future* writes and leave the existing
    /// history — the very thing the user asked not to keep — sitting in
    /// UserDefaults until something happened to overwrite it.
    private func observeHistoryPersistence() {
        persistenceCancellable = Defaults.publisher(.persistClipboardHistory, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    // Session-only images have no file yet; give them one so
                    // they survive the restart the user just opted into.
                    self.persistInMemoryImages()
                    self.saveHistoryToDefaults()
                    self.savePinnedItemsToDefaults()
                } else {
                    // Take the bytes into memory before the files go, or the
                    // items still on screen lose their images mid-session.
                    self.retainImagesInMemory()
                    ClipboardManager.removeStoredHistory()
                    self.removeUnpinnedImageFiles()
                }
            }
    }

    private static func removeStoredHistory() {
        UserDefaults.standard.removeObject(forKey: "ClipboardHistory")
    }

    /// Reads every history image into the in-memory store so the entries keep
    /// rendering and re-copying after their files are deleted.
    private func retainImagesInMemory() {
        for item in clipboardHistory {
            guard item.imageFileName != nil, let data = item.getImageData() else { continue }
            ClipboardItem.storeInMemoryImage(data, for: item.id)
        }
    }

    /// Gives session-only images a file on disk, so turning persistence back on
    /// keeps the images the current session captured rather than restoring
    /// entries whose picture is gone.
    private func persistInMemoryImages() {
        for index in clipboardHistory.indices where clipboardHistory[index].imageFileName == nil {
            clipboardHistory[index].imageFileName = persistImageFile(for: clipboardHistory[index].id)
        }

        for index in pinnedItems.indices where pinnedItems[index].imageFileName == nil {
            pinnedItems[index].imageFileName = persistImageFile(for: pinnedItems[index].id)
        }
    }

    /// Deletes image files written while persistence was on, so turning the
    /// setting off does not leave PNGs of past copies behind. Files backing
    /// pinned items are kept: pinning is an explicit request to keep something,
    /// and this setting is about history.
    private func removeUnpinnedImageFiles() {
        ClipboardManager.removeUnpinnedImageFiles(
            keeping: Set(pinnedItems.compactMap { $0.imageFileName })
        )
    }

    /// Erases saved history at launch when persistence is off, without building
    /// the manager. The instance is created lazily — often not until the user
    /// opens the clipboard, sometimes never — so leaving this to `init` would
    /// let history the user asked not to keep sit on disk for the whole
    /// session.
    static func purgeStoredHistoryIfPersistenceDisabled() {
        guard !Defaults[.persistClipboardHistory] else { return }
        removeStoredHistory()
        // The stored list was only half of it. The images it referred to are
        // separate PNGs, and this runs at launch precisely because the manager
        // is lazy -- so nothing else was going to delete them either, and the
        // pictures a user asked not to keep sat in Documents all session.
        removeUnpinnedImageFiles(keeping: storedPinnedImageFileNames())
    }

    /// The image files the *saved* pinned items refer to.
    ///
    /// Read from disk rather than from `pinnedItems`, because the purge above
    /// runs before there is a manager to ask -- which is the whole reason it
    /// is a launch step.
    private static func storedPinnedImageFileNames() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: "ClipboardPinnedItems"),
              let pinned = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return []
        }
        return Set(pinned.compactMap { $0.imageFileName })
    }

    /// Deletes every image in the data directory except the ones named.
    ///
    /// Pinning is a request to keep something regardless of the history
    /// setting, so a pinned item's file survives.
    private static func removeUnpinnedImageFiles(keeping keep: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: clipboardDataDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }
    
    /// Mark a drag-out as in progress and arm a bounded safety reset. SwiftUI `.onDrag`
    /// exposes no drag-end callback, so the notch is held open until this timeout fires;
    /// a true completion callback would require an AppKit `NSDraggingSource` (intentionally
    /// avoided here — see `ClipboardDragging.swift`).
    ///
    /// The window is a trade-off: too short and the notch closes mid-drag on a slow drag;
    /// too long and it stays pinned open (a leak) if the drop never completes. 8s comfortably
    /// covers a realistic drag-and-drop while keeping the worst-case leak short.
    static let dragSafetyResetTimeout: TimeInterval = 8.0

    func markDragStart() {
        isDraggingItem = true
        dragResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isDraggingItem = false }
        dragResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dragSafetyResetTimeout, execute: work)
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text, .url:
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        case .image:
            if let imageData = item.getImageData() {
                pasteboard.setData(imageData, forType: .png)
            }
        case .file:
            if let fileURLs = item.fileURLs {
                let urls = fileURLs.compactMap { URL(string: $0) }
                pasteboard.writeObjects(urls as [NSPasteboardWriting])
            }
        case .rtf:
            if let rtfData = item.rtfData {
                pasteboard.setData(rtfData, forType: .rtf)
            }
            // Also set plain text as fallback
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        case .unknown:
            if let stringData = item.stringData {
                pasteboard.setString(stringData, forType: .string)
            }
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        // Clean up associated files
        if let fileName = item.imageFileName {
            let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        clipboardHistory.removeAll { $0.id == item.id }
        saveHistoryToDefaults()
    }
    
    func clearHistory() {
        // Clean up all associated files
        for item in clipboardHistory {
            if let fileName = item.imageFileName {
                let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        clipboardHistory.removeAll()
        saveHistoryToDefaults()
    }
    
    /// Clears favorites, deleting the image files behind them.
    ///
    /// Callers used to empty `pinnedItems` and save directly, which left the
    /// PNG of every pinned image orphaned in `clipboardDataDirectory` forever —
    /// `clearHistory()` deletes files, this path did not.
    func clearPinnedItems() {
        for item in pinnedItems {
            guard let fileName = item.imageFileName else { continue }
            let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        pinnedItems.removeAll()
        savePinnedItemsToDefaults()
        ClipboardItem.pruneInMemoryImages(
            keeping: Set(clipboardHistory.map { $0.id })
        )
    }

    func pinItem(_ item: ClipboardItem) {
        // Update the item to be pinned
        var pinnedItem = item
        pinnedItem.isPinned = true
        
        // Remove from regular history if it exists there
        clipboardHistory.removeAll { $0.id == item.id }
        
        // Add to pinned items if not already there
        if !pinnedItems.contains(where: { $0.id == item.id }) {
            // While history is not being saved an image lives only in memory,
            // with no file behind it -- but the pinned record about to be
            // written names a file, and a restart would restore a pinned
            // entry with no picture in it. Pinning is a request to keep this
            // one thing, so this one image gets a file. The rest of the
            // session-only history stays in memory, since none of it was
            // asked to be kept.
            if pinnedItem.type == .image, pinnedItem.imageFileName == nil {
                pinnedItem.imageFileName = persistImageFile(for: pinnedItem.id)
            }
            pinnedItems.append(pinnedItem)
        }
        
        saveHistoryToDefaults()
        savePinnedItemsToDefaults()
    }

    /// Writes an in-memory image out and returns the file's name, or nil when
    /// there are no bytes held for the item or the write fails.
    private func persistImageFile(for id: UUID) -> String? {
        guard let data = ClipboardItem.inMemoryImage(for: id) else { return nil }
        let name = "clipboard_image_\(UUID().uuidString).png"
        let url = ClipboardManager.clipboardDataDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            print("Failed to persist clipboard image: \(error)")
            return nil
        }
    }
    
    func unpinItem(_ item: ClipboardItem) {
        // Remove from pinned items
        pinnedItems.removeAll { $0.id == item.id }
        
        // Update the item to be unpinned and add back to regular history
        var unpinnedItem = item
        unpinnedItem.isPinned = false
        
        // Add back to regular history at the top
        clipboardHistory.insert(unpinnedItem, at: 0)
        
        // Maintain history size limit
        if clipboardHistory.count > maxHistoryItems {
            let itemsToDelete = Array(clipboardHistory.dropFirst(maxHistoryItems))
            for oldItem in itemsToDelete {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            clipboardHistory = Array(clipboardHistory.prefix(maxHistoryItems))
        }
        
        saveHistoryToDefaults()
        savePinnedItemsToDefaults()
    }
    
    func togglePin(for item: ClipboardItem) {
        if item.isPinned || pinnedItems.contains(where: { $0.id == item.id }) {
            unpinItem(item)
        } else {
            pinItem(item)
        }
    }
    
    // MARK: - Private Methods
    
    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        guard let clipboardItem = getCurrentClipboardItem() else { return }
        
        // Don't add duplicate items
        if !clipboardHistory.contains(where: { isSameContent($0, clipboardItem) }) {
            addToHistory(clipboardItem)
        }
    }
    
    private func getCurrentClipboardItem() -> ClipboardItem? {
        let pasteboard = NSPasteboard.general
        
        // Step 1: Check what types are available
        let hasFileURLs = pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
        let hasImageData = pasteboard.data(forType: .png) != nil || 
                          pasteboard.data(forType: .tiff) != nil || 
                          pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) != nil
        let hasString = pasteboard.string(forType: .string) != nil
        
        // Step 2: Smart detection based on context
        
        // Priority 1: If there are file URLs AND the files are actual image files, treat as image files (from Finder)
        if hasFileURLs {
            if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let realFileURLs = fileURLs.filter { url in
                    return url.isFileURL && 
                           !url.path.contains("/.file/id=") && 
                           !url.path.contains("/tmp/") && 
                           !url.path.hasPrefix("/private/var/") && 
                           !url.path.contains("/ClipboardViewer") && 
                           FileManager.default.fileExists(atPath: url.path)
                }
                
                if !realFileURLs.isEmpty {
                    // Check if these are image files - if so, try to load the actual image data
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif"]
                    let imageFiles = realFileURLs.filter { url in
                        imageExtensions.contains(url.pathExtension.lowercased())
                    }
                    
                    // If we have image files from Finder, load the actual image data
                    if !imageFiles.isEmpty, let firstImageURL = imageFiles.first {
                        if let imageData = try? Data(contentsOf: firstImageURL) {
                            return ClipboardItem(imageData: imageData)
                        }
                    }
                    
                    // Otherwise, treat as file(s)
                    let urlStrings = realFileURLs.map { $0.absoluteString }
                    return ClipboardItem(fileURLs: urlStrings)
                }
            }
        }
        
        // Priority 2: If there's ONLY image data without file URLs (screenshots, direct image paste)
        if hasImageData && !hasFileURLs {
            if let imageData = pasteboard.data(forType: .png) {
                return ClipboardItem(imageData: imageData)
            } else if let imageData = pasteboard.data(forType: .tiff) {
                return ClipboardItem(imageData: imageData)
            } else if let imageData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
                return ClipboardItem(imageData: imageData)
            }
        }
        
        // Resolve any rich representation up front so the URL branch below can defer to it:
        // a formatted URL selection (e.g. a link copied from a rich-text editor or web page)
        // exposes an `https://` string *and* RTF/HTML, and must not be flattened to a bare URL.
        let richText = pasteboard.rtfDataWithFallback()

        // Priority 3: Plain-text URLs stay typed as `.url` (address-bar copies carry no RTF).
        // Only when there is no usable rich representation — otherwise the formatting wins.
        if let string = pasteboard.string(forType: .string), !string.isEmpty,
           richText == nil,
           string.hasPrefix("http://") || string.hasPrefix("https://") {
            return ClipboardItem(stringData: string, type: .url)
        }

        // Priority 4: Rich text. Must come before plain text: any rich copy also exposes a
        // `.string` representation, so checking plain text first would shadow rich content and
        // the item would lose its formatting at capture time. Capturing here keeps styled
        // `rtfData` with a plain-text fallback, so both drag-out and copy-back preserve
        // formatting. Prefer real RTF; otherwise synthesize it from HTML — browsers (GitHub,
        // web pages) put `public.html` on the pasteboard but no `public.rtf`, so without this
        // step the common "copy from a web page" case would still drop as plain text.
        if let richText {
            return ClipboardItem(rtfData: richText.rtf, plainText: richText.plain)
        }

        // Priority 5: Plain text
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return ClipboardItem(stringData: string, type: .text)
        }

        // Priority 6: If we have image data WITH file URLs (document thumbnails),
        // this is likely a document with a preview - ignore the thumbnail and treat as unknown
        if hasImageData && hasFileURLs {
            // This is likely a document with a thumbnail preview - we don't want the thumbnail
            return nil
        }

        // Priority 7: URL strings
        if let url = pasteboard.string(forType: .URL) {
            return ClipboardItem(stringData: url, type: .url)
        }
        
        return nil
    }
    
    private func addToHistory(_ item: ClipboardItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Remove any existing items with the same data
            let itemsToRemove = self.clipboardHistory.filter { existingItem in
                return self.isSameContent(existingItem, item)
            }
            
            // Clean up files for items being removed
            for oldItem in itemsToRemove {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            self.clipboardHistory.removeAll { existingItem in
                return self.isSameContent(existingItem, item)
            }
            
            // Add to beginning of array
            self.clipboardHistory.insert(item, at: 0)
            self.lastCopiedItemDate = item.timestamp
            
            // Keep only the most recent items and clean up old files
            let itemsToDelete = Array(self.clipboardHistory.dropFirst(self.maxHistoryItems))
            for oldItem in itemsToDelete {
                if let fileName = oldItem.imageFileName {
                    let fileURL = ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            if self.clipboardHistory.count > self.maxHistoryItems {
                self.clipboardHistory = Array(self.clipboardHistory.prefix(self.maxHistoryItems))
            }
            
            self.saveHistoryToDefaults()
        }
    }
    
    // Helper to compare clipboard items for duplicates
    private func isSameContent(_ item1: ClipboardItem, _ item2: ClipboardItem) -> Bool {
        if item1.type != item2.type { return false }
        
        switch item1.type {
        case .text, .url, .unknown:
            return item1.stringData == item2.stringData
        case .image:
            // For images, compare the actual data if both are available
            let data1 = item1.getImageData()
            let data2 = item2.getImageData()
            return data1 == data2
        case .file:
            return item1.fileURLs == item2.fileURLs
        case .rtf:
            return item1.stringData == item2.stringData && item1.rtfData == item2.rtfData
        }
    }
    
    // Clean up old image files that are no longer referenced
    private func cleanupOldFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: ClipboardManager.clipboardDataDirectory, includingPropertiesForKeys: nil) else { return }
        
        // Pinned items live in the same directory; leaving them out here
        // deleted the image behind every favorite on the next launch.
        let referencedFiles = Set(clipboardHistory.compactMap { $0.imageFileName })
            .union(pinnedItems.compactMap { $0.imageFileName })
        
        for file in files {
            let fileName = file.lastPathComponent
            if !referencedFiles.contains(fileName) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveHistoryToDefaults() {
        // Runs on every history mutation, so it is the natural place to drop
        // image bytes for items that are no longer around.
        ClipboardItem.pruneInMemoryImages(
            keeping: Set(clipboardHistory.map { $0.id }).union(pinnedItems.map { $0.id })
        )

        guard Defaults[.persistClipboardHistory] else {
            // Keep the session's history in memory, but leave nothing behind.
            ClipboardManager.removeStoredHistory()
            return
        }

        if let encoded = try? JSONEncoder().encode(clipboardHistory) {
            UserDefaults.standard.set(encoded, forKey: "ClipboardHistory")
        }
    }
    
    func savePinnedItemsToDefaults() {
        if let encoded = try? JSONEncoder().encode(pinnedItems) {
            UserDefaults.standard.set(encoded, forKey: "ClipboardPinnedItems")
        }
    }
    
    private func loadHistoryFromDefaults() {
        if Defaults[.persistClipboardHistory] {
            if let data = UserDefaults.standard.data(forKey: "ClipboardHistory"),
               let history = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
                clipboardHistory = history
            }
        } else {
            // Covers history stored before the setting was turned off, and any
            // written by an older build that did not know about it.
            ClipboardManager.removeStoredHistory()
        }
        
        if let data = UserDefaults.standard.data(forKey: "ClipboardPinnedItems"),
           let pinned = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            pinnedItems = pinned
        }
    }
}

private extension NSPasteboard {
    /// Extract rich text as RTF data plus a plain-text fallback, or `nil` when the pasteboard
    /// holds no rich content. Prefers a real `public.rtf` representation; when only HTML is
    /// present — browsers and sites like GitHub expose `public.html` but no `public.rtf` — the
    /// HTML is parsed into an attributed string and re-encoded as RTF so the formatting is
    /// captured instead of lost. Must be called on the main thread: HTML import spins up WebKit.
    func rtfDataWithFallback() -> (rtf: Data, plain: String)? {
        if let rtfData = data(forType: .rtf),
           let string = NSAttributedString(rtf: rtfData, documentAttributes: nil)?.string,
           !string.isEmpty {
            return (rtfData, string)
        }
        if let htmlData = data(forType: .html),
           let attributed = try? NSAttributedString(
               data: htmlData,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil),
           !attributed.string.isEmpty,
           let rtf = try? attributed.data(
               from: NSRange(location: 0, length: attributed.length),
               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            return (rtf, attributed.string)
        }
        return nil
    }
}
