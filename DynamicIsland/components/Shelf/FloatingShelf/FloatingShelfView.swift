/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import SwiftUI
import AppKit
import Defaults

/// A standalone SwiftUI view presenting the floating shelf container.
/// Allows dropping, inspecting, and dragging items out from any location on screen.
struct FloatingShelfView: View {
    /// Observed view model tracking the current shelf items.
    @ObservedObject var tvm = ShelfStateViewModel.shared

    /// State tracking whether a drag operation is currently hovering over the shelf.
    @State private var isTargeted = false

    /// Callback triggered when the close button is clicked.
    var onClose: () -> Void = {}

    /// Callback triggered when the "Dock to Notch" button is clicked.
    var onDockToNotch: () -> Void = {}

    /// Main SwiftUI body layout.
    var body: some View {
        VStack(spacing: 12) {
            // Header: Title and action buttons
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Floating Shelf")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)

                    if !tvm.items.isEmpty {
                        Text("\(tvm.items.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                    }
                }
                .contentShape(Rectangle())
                .floatingShelfWindowDraggable()

                Spacer()
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .floatingShelfWindowDraggable()

                HStack(spacing: 6) {
                    if !tvm.items.isEmpty {
                        Button {
                            tvm.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Clear All Items")

                        Button {
                            onDockToNotch()
                        } label: {
                            Image(systemName: "arrow.up.to.line.compact")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Dock to Notch (Move items into Dynamic Island)")
                    }

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Close Floating Shelf")
                }
            }
            .padding(.horizontal, 4)

            // Content Area
            if tvm.items.isEmpty {
                emptyDropTarget
            } else {
                itemsContent
            }

            // Footer hint
            HStack {
                Text(tvm.items.isEmpty ? "Shake mouse while dragging to summon • Drag anywhere to move" : "Drag anywhere to move • Double-click to open • Drag out to copy")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                Spacer()
            }
            .contentShape(Rectangle())
            .floatingShelfWindowDraggable()
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: isTargeted ? 2 : 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .floatingShelfWindowDraggable()
        )
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isTargeted) { providers in
            tvm.load(providers)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            return true
        }
    }

    // MARK: - Subviews

    /// Drop area placeholder displayed when no items are currently on the shelf.
    private var emptyDropTarget: some View {
        VStack(spacing: 8) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 28))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.55))
                .scaleEffect(isTargeted ? 1.12 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)

            Text(isTargeted ? "Release to drop files" : "Drop files here to stash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isTargeted ? .white : Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.white.opacity(0.12),
                            lineWidth: isTargeted ? 1.5 : 1
                        )
                )
        )
    }

    /// Horizontal scroll container rendering individual shelf item cards.
    private var itemsContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tvm.items) { item in
                    FloatingShelfItemCard(item: item)
                }

                // Add more drop slot
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.white.opacity(0.45))
                    Text("Add")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .frame(width: 72, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .frame(maxHeight: 92)
    }
}

// MARK: - Item Card with native Drag-Out and Double-Click Open

/// Card view representing a single shelf item within the floating shelf.
struct FloatingShelfItemCard: View {
    /// The shelf item represented by this card.
    let item: ShelfItem

    /// Tracks mouse hover state to reveal card controls.
    @State private var isHovering = false

    /// Card view body layout.
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                Image(nsImage: item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)

                Text(item.displayName.isEmpty ? "File" : item.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 68)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.14) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(isHovering ? 0.22 : 0.08), lineWidth: 1)
                    )
            )
            .overlay(
                FloatingNativeDragOverlay(
                    item: item,
                    onHover: { hovering in
                        withAnimation(.smooth(duration: 0.15)) {
                            isHovering = hovering
                        }
                    },
                    onDoubleClick: {
                        ShelfActionService.open(item)
                    }
                )
            )

            // Remove button on hover
            if isHovering {
                Button {
                    ShelfActionService.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .padding(2)
                .transition(.opacity)
                .zIndex(10)
                .help("Remove from shelf")
            }
        }
    }
}

// MARK: - Native AppKit Dragging Source Overlay

/// NSViewRepresentable bridging AppKit dragging and tracking capabilities to SwiftUI item cards.
struct FloatingNativeDragOverlay: NSViewRepresentable {
    /// The associated shelf item to drag.
    let item: ShelfItem

    /// Callback notifying parent view of hover state transitions.
    var onHover: ((Bool) -> Void)?

    /// Callback notifying parent view of a double-click activation.
    var onDoubleClick: () -> Void

    /// Creates and configures the native AppKit dragging source view.
    func makeNSView(context: Context) -> FloatingNativeDragNSView {
        let view = FloatingNativeDragNSView()
        view.item = item
        view.onHover = onHover
        view.onDoubleClick = onDoubleClick
        return view
    }

    /// Updates existing AppKit view configuration on SwiftUI state changes.
    func updateNSView(_ nsView: FloatingNativeDragNSView, context: Context) {
        nsView.item = item
        nsView.onHover = onHover
        nsView.onDoubleClick = onDoubleClick
    }
}

/// Custom NSView acting as an NSDraggingSource and tracking area owner for floating shelf cards.
final class FloatingNativeDragNSView: NSView, NSDraggingSource {
    /// The shelf item associated with this drag source.
    var item: ShelfItem?

    /// Closure called when mouse enters or exits this card view.
    var onHover: ((Bool) -> Void)?

    /// Closure called on a double-click gesture.
    var onDoubleClick: (() -> Void)?

    /// Initial mouse-down event to measure drag distance threshold.
    private var mouseDownEvent: NSEvent?

    /// Active mouse tracking area for hover observation.
    private var trackingArea: NSTrackingArea?

    /// Distance in points before a mouse drag initiates an AppKit dragging session.
    private let dragThreshold: CGFloat = 3.0

    /// Recomputes mouse tracking areas when view geometry updates.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    /// Handles cursor entering the card bounds.
    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    /// Handles cursor leaving the card bounds.
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    /// Yields hit-testing for the top-right corner to allow delete button interactions.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let cornerSize: CGFloat = 26
        let cornerRect = NSRect(
            x: bounds.maxX - cornerSize,
            y: bounds.maxY - cornerSize,
            width: cornerSize,
            height: cornerSize
        )
        if cornerRect.contains(point) {
            return nil
        }
        return super.hitTest(point)
    }

    /// Captures mouse-down events and handles double-click item opening.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        mouseDownEvent = event
    }

    /// Monitors mouse movement to initiate dragging once the distance threshold is exceeded.
    override func mouseDragged(with event: NSEvent) {
        guard let initial = mouseDownEvent, let item = item else {
            super.mouseDragged(with: event)
            return
        }
        let distance = hypot(
            event.locationInWindow.x - initial.locationInWindow.x,
            event.locationInWindow.y - initial.locationInWindow.y
        )
        if distance > dragThreshold {
            self.mouseDownEvent = nil
            startDrag(with: event, item: item)
        } else {
            super.mouseDragged(with: event)
        }
    }

    /// Resets mouse-down tracking upon button release.
    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }

    /// Initiates a system dragging session for the specified shelf item.
    /// - Parameters:
    ///   - event: The mouse event that triggered the drag.
    ///   - item: The shelf item being dragged.
    private func startDrag(with event: NSEvent, item: ShelfItem) {
        var draggingItems: [NSDraggingItem] = []
        let icon = item.icon
        let iconSize = NSSize(width: 44, height: 44)
        let originX = max(0, (bounds.width - iconSize.width) / 2)
        let originY = max(0, bounds.height - iconSize.height - 12)
        let dragFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: iconSize)

        if let url = item.resolvedFileURL {
            let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            dragItem.setDraggingFrame(dragFrame, contents: icon)
            draggingItems.append(dragItem)
        } else if case .link(let u) = item.kind {
            let dragItem = NSDraggingItem(pasteboardWriter: u as NSURL)
            dragItem.setDraggingFrame(dragFrame, contents: icon)
            draggingItems.append(dragItem)
        } else if case .text(let s) = item.kind {
            let dragItem = NSDraggingItem(pasteboardWriter: s as NSString)
            dragItem.setDraggingFrame(dragFrame, contents: icon)
            draggingItems.append(dragItem)
        }

        guard !draggingItems.isEmpty else { return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    /// Determines permissible drag operations based on external versus internal destination context.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            // Safe copy by default to prevent Finder from moving/deleting files on same volume
            let allowsMove = Defaults[.allowMoveOnDrag] && !Defaults[.copyOnDrag]
            return allowsMove ? [.copy, .move] : [.copy]
        case .withinApplication:
            return Defaults[.copyOnDrag] ? [.copy] : [.copy, .move, .generic]
        @unknown default:
            return [.copy]
        }
    }

    /// Handles completion of a dragging session, auto-removing items if configured.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
            if let item = item {
                ShelfStateViewModel.shared.remove(item)
            }
        }
    }
}

// MARK: - Window Dragging Modifier

/// Modifier enabling window dragging via native SwiftUI WindowDragGesture on macOS 15+.
private struct FloatingShelfWindowDragModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content
        }
    }
}

private extension View {
    /// Makes the view surface draggable to move the host window.
    func floatingShelfWindowDraggable() -> some View {
        modifier(FloatingShelfWindowDragModifier())
    }
}

