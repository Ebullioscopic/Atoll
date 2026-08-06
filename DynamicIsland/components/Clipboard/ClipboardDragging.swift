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
    func dragItemProvider() -> NSItemProvider {
        switch type {
        case .text, .url, .unknown, .rtf:
            // RTF drags as plain text for now; rich-text fidelity is a later refinement.
            if let string = stringData { return NSItemProvider(object: string as NSString) }
        case .image:
            if let url = imageFileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
        case .file:
            // SwiftUI `.onDrag` yields a single provider, so a multi-file item drags its
            // first URL for now; multi-file drag-out is a later refinement.
            if let first = fileURLs?.compactMap({ URL(string: $0) }).first,
               let provider = NSItemProvider(contentsOf: first) { return provider }
        }
        return NSItemProvider()
    }
}

extension View {
    /// Make a clipboard row draggable out to Finder / other apps (drag = copy).
    /// Marks a drag in progress so the notch does not auto-close mid-drag
    /// (see `ClipboardManager.isDraggingItem` in `shouldPreventAutoClose`).
    func clipboardDraggable(_ item: ClipboardItem) -> some View {
        self.onDrag {
            ClipboardManager.shared.markDragStart()
            return item.dragItemProvider()
        }
    }
}
