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
import SwiftUI
import Defaults

import QuickLook

/// Layout metrics for the hover-revealed remove (x) button on a shelf item.
/// Shared between the SwiftUI overlay and the AppKit drag view's hit-testing so
/// the corner the button occupies is excluded from the drag/click handler.
private enum ShelfRemoveButton {
    /// Diameter of the circular remove button.
    static let size: CGFloat = 20
    /// Inset of the button from the item's top-trailing corner.
    static let inset: CGFloat = 2
    /// Square corner region (top-trailing) reserved for the button while
    /// hovering, so clicks there hit the button instead of the drag view.
    static let hitRegion: CGFloat = 30
}

struct ShelfItemView: View {
    let item: ShelfItem
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var selection = ShelfSelectionModel.shared
    @StateObject private var viewModel: ShelfItemViewModel
    @EnvironmentObject private var quickLookService: QuickLookService
    @State private var showStack = false
    @State private var cachedPreviewImage: NSImage?
    @State private var debouncedDropTarget = false
    @State private var isHovering = false

    private var isSelected: Bool { viewModel.isSelected }
    private var shouldHideDuringDrag: Bool { selection.isDragging && selection.isSelected(item.id) && false }
    
    init(item: ShelfItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: ShelfItemViewModel(item: item))
    }

    var body: some View {
        ZStack {
            if !shouldHideDuringDrag {
                VStack(alignment: .center, spacing: 2) {
                    iconView
                    textView
                }
                .frame(width: 105)
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
                .background(backgroundView)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.1), value: debouncedDropTarget)
                .animation(.easeInOut(duration: 0.1), value: isSelected)
                .overlay(alignment: .topTrailing) {
                    if isHovering {
                        removeButton
                    }
                }
                // Keep removal reachable without hover (VoiceOver / keyboard):
                // expose the item as one element with a named remove action.
                .accessibilityElement(children: .combine)
                .accessibilityLabel(viewModel.displayName.isEmpty ? Text("Shelf item") : Text(viewModel.displayName))
                .accessibilityAction(named: Text("Remove from Shelf")) {
                    ShelfActionService.remove(item)
                }

                DraggableClickHandler(
                    item: item,
                    viewModel: viewModel,
                    isHovering: isHovering,
                    // Hover is detected here (in the AppKit drag view via a
                    // tracking area) rather than with SwiftUI's `.onHover`,
                    // because this NSView sits on top of the cell and
                    // intercepts the mouse-tracking `.onHover` would need.
                    onHoverChange: { hovering in
                        withAnimation(.smooth(duration: 0.15)) {
                            isHovering = hovering
                        }
                    },
                    cachedPreviewImage: $cachedPreviewImage,
                    dragPreviewContent: {
                        DragPreviewView(thumbnail: viewModel.thumbnail ?? viewModel.icon, displayName: viewModel.displayName)
                    },
                    onRightClick: viewModel.handleRightClick,
                    onClick: { event, nsview in
                        viewModel.handleClick(event: event, view: nsview)
                    },
                    // `isDragging` kept the notch open for the duration of the
                    // drag; the hover-exit that would have closed it already
                    // came and went, so ask for a fresh evaluation.
                    onDragEnded: { vm.shouldRecheckHover.toggle() }
                )
            } else {
                Color.clear
                    .frame(width: 105)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 5)
            }
        }
        .onChange(of: viewModel.isDropTargeted) { _, targeted in
            vm.dragDetectorTargeting = targeted
            // Debounce drop target state changes
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                debouncedDropTarget = targeted
            }
        }
        .onAppear {
            // Metadata loading is now done in ViewModel.init via loadMetadata()
            // Pre-render drag preview once on appear
            Task {
                if cachedPreviewImage == nil {
                    cachedPreviewImage = await renderDragPreview()
                }
            }
            viewModel.onQuickLookRequest = { urls in
                quickLookService.show(urls: urls, selectFirst: true)
            }
        }
        .onChange(of: viewModel.thumbnail) { _, _ in
            // Invalidate cached preview when thumbnail changes
            Task {
                cachedPreviewImage = await renderDragPreview()
            }
        }
        .quickLookPresenter(using: quickLookService)
    }

    // MARK: - View Components

    private var iconView: some View {
        Image(nsImage: viewModel.thumbnail ?? viewModel.icon ?? NSImage())
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
    }

    private var textView: some View {
        Text(viewModel.displayName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .truncationMode(.middle)
            .multilineTextAlignment(.center)
            .frame(height: 30, alignment: .top)
    }

    /// Hover-revealed circular remove button in the top-trailing corner.
    /// Removes just this item from the shelf via the same path as the
    /// right-click "Remove" menu item (`ShelfActionService.remove`).
    /// Uses a `Button` (not a bare tap gesture) so it carries button
    /// semantics for VoiceOver; the item also exposes a hover-independent
    /// "Remove from Shelf" accessibility action (see `body`).
    private var removeButton: some View {
        Button {
            ShelfActionService.remove(item)
        } label: {
            Circle()
                .fill(.white)
                .frame(width: ShelfRemoveButton.size, height: ShelfRemoveButton.size)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                )
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .padding(ShelfRemoveButton.inset)
        .help("Remove from Shelf")
        .accessibilityLabel("Remove from Shelf")
        .transition(.scale.combined(with: .opacity))
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        strokeColor,
                        lineWidth: strokeWidth
                    )
            )
    }

    private var backgroundColor: Color {
        if debouncedDropTarget {
            return Color.accentColor.opacity(0.25)
        } else if isSelected {
            return Color.accentColor.opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private var strokeColor: Color {
        if debouncedDropTarget {
            return Color.accentColor.opacity(0.9)
        } else if isSelected {
            return Color.accentColor.opacity(0.8)
        } else {
            return Color.clear
        }
    }

    private var strokeWidth: CGFloat {
        if debouncedDropTarget {
            return 3
        } else if isSelected {
            return 2
        } else {
            return 1
        }
    }
    
    // MARK: - Drag Preview Rendering
    
    @MainActor
    private func renderDragPreview() async -> NSImage {
        let content = DragPreviewView(thumbnail: viewModel.thumbnail ?? viewModel.icon ?? NSImage(), displayName: viewModel.displayName)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? (viewModel.thumbnail ?? viewModel.icon ?? NSImage())
    }

    
}

// MARK: - Draggable Click Handler with NSDraggingSource
private struct DraggableClickHandler<Content: View>: NSViewRepresentable {
    let item: ShelfItem
    let viewModel: ShelfItemViewModel
    let isHovering: Bool
    let onHoverChange: (Bool) -> Void
    @Binding var cachedPreviewImage: NSImage?
    @ViewBuilder let dragPreviewContent: () -> Content
    let onRightClick: (NSEvent, NSView) -> Void
    let onClick: (NSEvent, NSView) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DraggableClickView {
        let view = DraggableClickView()
        view.item = item
        view.viewModel = viewModel
        view.isHovering = isHovering
        view.onHoverChange = onHoverChange
        view.dragPreviewImage = cachedPreviewImage ?? renderDragPreview()
        view.onRightClick = onRightClick
        view.onClick = onClick
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DraggableClickView, context: Context) {
        nsView.item = item
        nsView.viewModel = viewModel
        nsView.isHovering = isHovering
        nsView.onHoverChange = onHoverChange
        // Only update preview if cached version is available
        if let cached = cachedPreviewImage {
            nsView.dragPreviewImage = cached
        }
        nsView.onRightClick = onRightClick
        nsView.onClick = onClick
        nsView.onDragEnded = onDragEnded
    }
    
    private func renderDragPreview() -> NSImage {
        let content = dragPreviewContent()
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        
        if let nsImage = renderer.nsImage {
            return nsImage
        }
        
        // Fallback to icon if rendering fails
        return viewModel.thumbnail ?? viewModel.icon ?? NSImage()
    }
    
    final class DraggableClickView: NSView, NSDraggingSource {
        // Registered with `ShelfItemHitRegistry` so marquee selection can read
        // this cell's frame without walking the view hierarchy.
        var item: ShelfItem! {
            didSet {
                guard let id = item?.id, id != oldValue?.id else { return }
                if let old = oldValue?.id {
                    ShelfItemHitRegistry.shared.unregister(old, view: self)
                }
                if window != nil {
                    ShelfItemHitRegistry.shared.register(self, for: id)
                }
            }
        }
        weak var viewModel: ShelfItemViewModel?
        var dragPreviewImage: NSImage?
        var onRightClick: ((NSEvent, NSView) -> Void)?
        var onClick: ((NSEvent, NSView) -> Void)?
        var onDragEnded: (() -> Void)?
        var onHoverChange: ((Bool) -> Void)?
        var isHovering = false

        private var mouseDownEvent: NSEvent?
        private let dragThreshold: CGFloat = ShelfDragMetrics.threshold
        private var draggedItems: [ShelfItem] = []
        private var didStartDragSession = false

        // Detect hover here (this NSView sits on top of the cell and would
        // otherwise swallow the mouse tracking SwiftUI's `.onHover` relies on).
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let id = item?.id else { return }
            if window != nil {
                ShelfItemHitRegistry.shared.register(self, for: id)
            } else {
                ShelfItemHitRegistry.shared.unregister(id, view: self)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange?(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // While hovering, yield the top-trailing corner to the SwiftUI
            // remove (x) button drawn beneath this drag view, so tapping it
            // removes the item instead of opening it or starting a drag.
            if isHovering {
                let local = convert(point, from: superview)
                let corner = NSRect(
                    x: bounds.maxX - ShelfRemoveButton.hitRegion,
                    y: bounds.maxY - ShelfRemoveButton.hitRegion,
                    width: ShelfRemoveButton.hitRegion,
                    height: ShelfRemoveButton.hitRegion
                )
                if corner.contains(local) { return nil }
            }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?(event, self)
        }
        
        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            didStartDragSession = false
        }

        override func mouseUp(with event: NSEvent) {
            defer {
                mouseDownEvent = nil
                didStartDragSession = false
            }

            guard let mouseDownEvent, !didStartDragSession else {
                super.mouseUp(with: event)
                return
            }

            onClick?(mouseDownEvent, self)
        }
        
        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent = mouseDownEvent else {
                super.mouseDragged(with: event)
                return
            }
            
            let dragDistance = hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
            )
            
            if dragDistance > dragThreshold {
                didStartDragSession = true
                prepareSelectionForDrag(using: mouseDownEvent)
                startDragSession(with: event)
                self.mouseDownEvent = nil
            } else {
                super.mouseDragged(with: event)
            }
        }

        private func prepareSelectionForDrag(using initialEvent: NSEvent) {
            let flags = initialEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags.contains(.shift) || flags.contains(.command) || flags.contains(.control) {
                return
            }

            if !ShelfSelectionModel.shared.isSelected(item.id) {
                ShelfSelectionModel.shared.selectSingle(item)
            }
        }
        
        private func startDragSession(with event: NSEvent) {
            // Prepare dragging items
            let selectedItems = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
            let itemsToDrag: [ShelfItem]

            if selectedItems.count > 1 && selectedItems.contains(where: { $0.id == item.id }) {
                itemsToDrag = selectedItems
            } else {
                itemsToDrag = [item]
            }

            // Store items being dragged for auto-remove feature
            draggedItems = itemsToDrag

            // Create dragging items for AppKit
            var draggingItems: [NSDraggingItem] = []

            for dragItem in itemsToDrag {
                guard let writer = pasteboardWriter(for: dragItem) else {
                    NSLog("⚠️ Skipping shelf item in drag: could not resolve a URL for \(dragItem.id)")
                    continue
                }
                let draggingItem = NSDraggingItem(pasteboardWriter: writer)

                // Use the drag preview image
                let image = dragPreviewImage ?? dragItem.icon
                let imageFrame = NSRect(
                    x: 0,
                    y: 0,
                    width: image.size.width,
                    height: image.size.height
                )
                draggingItem.setDraggingFrame(imageFrame, contents: image)

                draggingItems.append(draggingItem)
            }

            guard !draggingItems.isEmpty else { return }

            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        /// `resolvedFileURL` reads the path captured at drop time, which is the
        /// path every item dropped or backfilled since launch has. Only when that
        /// is missing does it fall back to a synchronous `resolveWithoutMounting()`
        /// — still a main-actor bookmark resolve that can block, just bounded away
        /// from mounting an absent volume.
        ///
        /// This used to build an `NSPasteboardItem` by hand after a 5s
        /// semaphore wait that always deadlocked, so it fell through to writing
        /// `item.displayName` as plain text — which is why dropping onto Finder
        /// or Mail produced text instead of the file. Handing AppKit the
        /// `NSURL` instead declares `public.file-url`, `public.url`,
        /// `public.url-name` and the legacy filenames binding in one go, which
        /// is what Finder, Mail attachments and Slack uploads actually look for.
        ///
        /// Returning nil (rather than degrading to text) keeps an unresolvable
        /// item out of the drag entirely.
        private func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting? {
            switch item.kind {
            case .file:
                guard let url = item.resolvedFileURL else { return nil }
                return url as NSURL
            case .text(let string):
                return string as NSString
            case .link(let url):
                return url as NSURL
            }
        }
        
        // MARK: - NSDraggingSource
        
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                // Copy by default. AppKit has no way to say "move is allowed but
                // prefer copy" — the destination decides — and Finder moves by
                // default whenever the target sits on the same volume. That
                // silently relocated the user's original file, so moving is now
                // opt-in via `allowMoveOnDrag`.
                let allowsMove = Defaults[.allowMoveOnDrag] && !Defaults[.copyOnDrag]
                return allowsMove ? [.copy, .move] : [.copy]
            case .withinApplication:
                return Defaults[.copyOnDrag] ? [.copy] : [.copy, .move, .generic]
            @unknown default:
                return [.copy]
            }
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            ShelfSelectionModel.shared.beginDrag()
        }


        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            ShelfSelectionModel.shared.endDrag()

            // Auto-remove items from shelf if enabled and drag succeeded
            if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
                for item in draggedItems {
                    ShelfStateViewModel.shared.remove(item)
                }
            }
            draggedItems.removeAll()
            onDragEnded?()
        }
        
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            return false
        }
    }
}
