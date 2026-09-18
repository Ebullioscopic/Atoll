/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import SwiftUI
import AppKit
import Defaults

struct FloatingShelfView: View {
    @ObservedObject var tvm = ShelfStateViewModel.shared
    @State private var isTargeted = false
    var onClose: () -> Void = {}
    var onDockToNotch: () -> Void = {}

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

                Spacer()

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
                        .help("Dock to Notch")
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
        )
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isTargeted) { providers in
            tvm.load(providers)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            return true
        }
    }

    // MARK: - Subviews

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
struct FloatingShelfItemCard: View {
    let item: ShelfItem
    @State private var isHovering = false

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
struct FloatingNativeDragOverlay: NSViewRepresentable {
    let item: ShelfItem
    var onHover: ((Bool) -> Void)?
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> FloatingNativeDragNSView {
        let view = FloatingNativeDragNSView()
        view.item = item
        view.onHover = onHover
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: FloatingNativeDragNSView, context: Context) {
        nsView.item = item
        nsView.onHover = onHover
        nsView.onDoubleClick = onDoubleClick
    }
}

final class FloatingNativeDragNSView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var onHover: ((Bool) -> Void)?
    var onDoubleClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?
    private var trackingArea: NSTrackingArea?
    private let dragThreshold: CGFloat = 3.0

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

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Yield top-right corner to the remove button
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

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        mouseDownEvent = event
    }

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

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        super.mouseUp(with: event)
    }

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

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
            if let item = item {
                ShelfStateViewModel.shared.remove(item)
            }
        }
    }
}
