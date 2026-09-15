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

import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ClipboardItem {
    /// On-disk URL of the temporary PNG backing an image item (nil for other types).
    var imageFileURL: URL? {
        guard let fileName = imageFileName else { return nil }
        return ClipboardManager.clipboardDataDirectory.appendingPathComponent(fileName)
    }

    /// Build the drag payload for this item, mirroring `copyToClipboard`'s per-type
    /// handling. Handing AppKit a file URL (image PNG / file) via `contentsOf:` declares
    /// both `public.file-url` and the file's data type in one go, so Finder receives a
    /// real file while apps still get the image/text — which is exactly what an
    /// iPhone-via-Universal-Clipboard image needs to be droppable anywhere.
    /// True for a `.file` entry that holds more than one URL. A single SwiftUI `.onDrag`
    /// provider can't carry multiple files, so such entries are not made draggable.
    var isMultiFile: Bool { type == .file && (fileURLs?.count ?? 0) > 1 }

    func dragItemProvider() -> NSItemProvider {
        switch type {
        case .rtf:
            // Offer the styled RTF alongside a plain-text fallback so a rich-text editor
            // (TextEdit, Pages, Word…) keeps the formatting while a plain-text field still
            // resolves the drop. RTF is registered first so it takes priority when the
            // target supports both. Falls through to plain text if the RTF bytes are missing.
            if let rtfData, let string = stringData {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier,
                                                    visibility: .all) { completion in
                    completion(rtfData, nil)
                    return nil
                }
                provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier,
                                                    visibility: .all) { completion in
                    completion(Data(string.utf8), nil)
                    return nil
                }
                return provider
            }
            if let string = stringData { return NSItemProvider(object: string as NSString) }
        case .text, .url, .unknown:
            if let string = stringData { return NSItemProvider(object: string as NSString) }
        case .image:
            if let provider = imageDragProvider() { return provider }
        case .file:
            // Multi-file entries are gated out in `clipboardDraggable`, so only single-file
            // items reach here.
            if let first = fileURLs?.compactMap({ URL(string: $0) }).first,
               let provider = NSItemProvider(contentsOf: first) { return provider }
        }
        // Fallback when a payload is unavailable (nil string, missing image file, unparsable
        // URL): drag the preview text rather than an empty provider, so the drag isn't a
        // no-op that follows the cursor and drops nothing.
        return NSItemProvider(object: preview as NSString)
    }

    /// Copy the persisted PNG to a temporary file before handing it to the drag, so an
    /// eviction or `deleteItem`/`clearHistory` that removes the Documents-backed original
    /// mid-drag can't make the drop resolve a missing file.
    private func imageDragProvider() -> NSItemProvider? {
        guard let source = imageFileURL else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(source.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        guard (try? FileManager.default.copyItem(at: source, to: tmp)) != nil else {
            return NSItemProvider(contentsOf: source) // fall back to the original
        }
        return NSItemProvider(contentsOf: tmp)
    }
}

extension View {
    /// Make a clipboard row draggable out to Finder / other apps (drag = copy).
    /// Marks a drag in progress so the notch does not auto-close mid-drag
    /// (see `ClipboardManager.isDraggingItem` in `shouldPreventAutoClose`).
    /// Multi-file entries are left non-draggable: a single `.onDrag` provider can't carry
    /// more than one file, so dragging one would silently copy only the first.
    @ViewBuilder
    func clipboardDraggable(_ item: ClipboardItem) -> some View {
        if item.isMultiFile {
            self
        } else {
            self.onDrag {
                ClipboardManager.shared.markDragStart()
                return item.dragItemProvider()
            }
        }
    }
}
