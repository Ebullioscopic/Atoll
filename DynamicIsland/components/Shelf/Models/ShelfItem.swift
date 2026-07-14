/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Foundation

enum ShelfItemKind: Codable, Equatable, Sendable {
    case file(bookmark: Data)
    case text(string: String)
    case link(url: URL)

    enum CodingKeys: String, CodingKey { case type, value }

    enum KindTag: String, Codable { case file, text, link }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .file:
            let data = try container.decode(Data.self, forKey: .value)
            self = .file(bookmark: data)
        case .text:
            self = .text(string: try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(url: try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let bookmark):
            try container.encode(KindTag.file, forKey: .type)
            try container.encode(bookmark, forKey: .value)
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        }
    }

}

@MainActor
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    var isTemporary: Bool
    // Cached display name and icon to avoid blocking on bookmark resolution
    var cachedDisplayName: String?
    var cachedIconData: Data?
    init(id: UUID = UUID(), kind: ShelfItemKind, isTemporary: Bool = false, cachedDisplayName: String? = nil, cachedIconData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
        self.cachedDisplayName = cachedDisplayName
        self.cachedIconData = cachedIconData
    }
    
    var displayName: String {
        switch kind {
        case .file(let bookmarkData):
            if let cached = cachedDisplayName, !cached.isEmpty {
                return cached
            }
            // No synchronous fallback - return empty string if not cached
            // Async resolution should be done via loadDisplayName()
            return ""
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url):
            let s = url.absoluteString
            if s.hasPrefix("https://") {
                return String(s.dropFirst("https://".count))
            } else if s.hasPrefix("http://") {
                return String(s.dropFirst("http://".count))
            } else {
                return s
            }
        }
    }
    
    var fileURL: URL? {
        guard case .file = kind else { return nil }
        // Don't resolve synchronously - use async method from ShelfStateViewModel
        return nil
    }
    
    var URL: URL? {
        if case let .file(bookmark) = kind { 
            // Don't resolve synchronously
            return nil
        } else if case let .link(url) = kind { 
            return url 
        } else { 
            return nil 
        }
    }
    
    var icon: NSImage {
        if let cachedData = cachedIconData, let cachedImage = NSImage(data: cachedData) {
            return cachedImage
        }
        guard case .file = kind else {
            return Self.thumbnailSymbolImage(systemName: kind.iconSymbolName) ?? NSImage()
        }
        // Return generic file icon instead of blocking on bookmark resolution
        return NSWorkspace.shared.icon(forFileType: "public.item")
    }
    
    // Async methods to load display name and icon without blocking
    func loadDisplayName() async -> String {
        // If we have a cached name, return it
        if let cached = cachedDisplayName, !cached.isEmpty {
            return cached
        }
        // Otherwise try to resolve asynchronously
        guard case .file(let bookmarkData) = kind else { return displayName }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        guard let resolvedURL = url else { return "" }
        
        // Perform file I/O off the main actor
        return await Task.detached { [resolvedURL] in
            if resolvedURL.pathExtension.lowercased() == "json" && resolvedURL.path.contains("TextBlocks") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    struct TextBlockData: Codable {
                        let content: String
                        let title: String?
                        var displayTitle: String {
                            if let title = title, !title.isEmpty {
                                return title
                            }
                            let firstLine = content.components(separatedBy: .newlines).first ?? content
                            if firstLine.count > 50 {
                                return String(firstLine.prefix(47)) + "..."
                            }
                            return firstLine
                        }
                    }
                    if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                        return textData.displayTitle
                    }
                } catch {
                    // Fall through
                }
            } else if resolvedURL.pathExtension.lowercased() == "webloc" && resolvedURL.path.contains("WebLocs") {
                do {
                    let data = try Data(contentsOf: resolvedURL)
                    if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let urlString = plist["URL"] as? String {
                        let title = plist["Title"] as? String
                        return title ?? urlString
                    }
                } catch {
                    // Fall through
                }
            }
            return (try? resolvedURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? resolvedURL.lastPathComponent
        }.value
    }
    
    func loadIcon() async -> NSImage {
        if let cachedData = cachedIconData, let cachedImage = NSImage(data: cachedData) {
            return cachedImage
        }
        guard case .file(let bookmarkData) = kind else {
            return Self.thumbnailSymbolImage(systemName: kind.iconSymbolName) ?? NSImage()
        }
        let bookmark = Bookmark(data: bookmarkData)
        let (url, _) = await bookmark.resolveAsync()
        guard let resolvedURL = url else {
            return NSWorkspace.shared.icon(forFileType: "public.item")
        }
        
        // Perform icon loading off the main actor
        return await Task.detached { [resolvedURL] in
            return NSWorkspace.shared.icon(forFile: resolvedURL.path)
        }.value
    }

    func cleanupStoredData() {
        // Only resolve bookmark for temporary items - persisted items don't need cleanup
        guard isTemporary, case let .file(bookmark) = kind,
              let context = resolvedContextSync(for: bookmark) else { return }
        
        let url = context.url
        
        // Handle temporary files
        TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
    }
}

private extension ShelfItem {
   static func thumbnailSymbolImage(
        systemName: String,
    size: CGSize = CGSize(width: 64, height: 80), 
    symbolPointSize: CGFloat = 38,
    backgroundColor: NSColor = NSColor.white,
    symbolColor: NSColor = NSColor.labelColor
    ) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = min(size.width, size.height) * 0.06
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        if let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let symbolSize = CGSize(width: symbolPointSize, height: symbolPointSize)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            let symbolRect = CGRect(origin: symbolOrigin, size: symbolSize)
            symbol.draw(in: symbolRect)
        }

        return image
    }
}

// MARK: - Identity key for deduplication
extension ShelfItem {
    var identityKey: String {
        switch kind {
        case .file(let bookmark):
            if let url = resolvedContextSync(for: bookmark)?.url {
                return "file://" + url.standardizedFileURL.path
            }
            return "file://missing/" + bookmark.base64EncodedString()
        case .link(let u):
            return "link://" + u.absoluteString
        case .text(let s):
            return "text://" + s
        }
    }
}

// MARK: - Private helpers
private extension ShelfItemKind {
    var iconSymbolName: String {
        switch self {
        case .file:
            return "questionmark.circle"
        case .text:
            return "text.justifyleft"
        case .link:
            return "link"
        }
    }
}

private extension ShelfItem {
    func resolvedContext(for bookmarkData: Data) async -> (url: URL, bookmark: Data)? {
        let bookmark = Bookmark(data: bookmarkData)
        let result = await bookmark.resolveAsync()
        if let url = result.url {
            return (url, result.refreshedData ?? bookmarkData)
        }
        return nil
    }

    // Sync wrapper for backward compatibility
    func resolvedContextSync(for bookmarkData: Data) -> (url: URL, bookmark: Data)? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: (url: URL, bookmark: Data)?
        Task.detached {
            result = await resolvedContext(for: bookmarkData)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5.0)
        return result
    }
}
