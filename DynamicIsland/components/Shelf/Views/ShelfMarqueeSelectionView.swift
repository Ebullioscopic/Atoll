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

/// Shared drag thresholds for the shelf. Dragging a file out and rubber-band
/// selecting use the same value so the boundary between the two gestures feels
/// consistent.
enum ShelfDragMetrics {
    static let threshold: CGFloat = 3.0
}

/// Rubber-band (marquee) selection over the shelf's empty space.
///
/// Mounted as an `.overlay` on the ScrollView's content — inside the document
/// view, above the cells — rather than at the bottom of `ShelfView`'s ZStack.
/// Sitting underneath, a `mouseDown` in the gap right of the last item would go
/// to the NSScrollView and travel *up* the responder chain, never reaching a
/// sibling below, so the most common way to start a marquee would never fire.
/// It would also draw the band beneath the item icons. From here instead:
/// empty-space `mouseDown` is guaranteed; `hitTest` returns nil over cells so
/// clicks still reach the drag view; `scrollWheel` isn't overridden and reaches
/// the clip view normally; and all geometry is already in scroll-content space.
///
/// Plain AppKit rather than SwiftUI's `DragGesture`: the cells are covered by
/// `DraggableClickView` (a real NSView that swallows mouse events), where a
/// SwiftUI gesture would never fire, and drawing the band in `draw(_:)` avoids
/// republishing SwiftUI state on every mouse-moved event.
struct ShelfMarqueeSelectionView: NSViewRepresentable {
    /// Fired when the press was a plain click, not a drag — preserves the
    /// existing "click the background to clear the selection" behavior.
    let onBackgroundClick: () -> Void
    /// Marquee started/finished; used to hold the notch open while dragging.
    let onActiveChange: (Bool) -> Void

    func makeNSView(context: Context) -> MarqueeView {
        let view = MarqueeView()
        view.onBackgroundClick = onBackgroundClick
        view.onActiveChange = onActiveChange
        return view
    }

    func updateNSView(_ nsView: MarqueeView, context: Context) {
        nsView.onBackgroundClick = onBackgroundClick
        nsView.onActiveChange = onActiveChange
    }

    static func dismantleNSView(_ nsView: MarqueeView, coordinator: ()) {
        nsView.forceFinish(cancelled: true)
    }

    final class MarqueeView: NSView {
        var onBackgroundClick: (() -> Void)?
        var onActiveChange: ((Bool) -> Void)?

        private var anchorPoint: NSPoint?
        private var currentRect: NSRect?
        private var isActive = false
        private var upMonitor: Any?
        private var autoScrollTimer: Timer?
        private var lastDragPointInWindow: NSPoint = .zero

        private let autoScrollEdge: CGFloat = 24
        private let autoScrollMaxStep: CGFloat = 12

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { true }

        // MARK: - Hit testing

        /// Yield points over item cells: a drag that begins on a cell means
        /// "drag this file out" and belongs to `DraggableClickView`. The marquee
        /// only starts from empty space. Once it's running we claim everything,
        /// so the band doesn't lose events when it sweeps across a cell.
        override func hitTest(_ point: NSPoint) -> NSView? {
            if isActive { return self }

            guard let superview else { return nil }
            let local = convert(point, from: superview)
            guard bounds.contains(local) else { return nil }

            let overItem = ShelfItemHitRegistry.shared
                .frames(in: self)
                .contains { $0.frame.contains(local) }
            return overItem ? nil : self
        }

        // MARK: - Mouse

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            anchorPoint = convert(event.locationInWindow, from: nil)
            currentRect = nil
            isActive = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let anchor = anchorPoint else {
                super.mouseDragged(with: event)
                return
            }

            let point = convert(event.locationInWindow, from: nil)
            let distance = hypot(point.x - anchor.x, point.y - anchor.y)

            if !isActive {
                guard distance > ShelfDragMetrics.threshold else {
                    super.mouseDragged(with: event)
                    return
                }
                startMarquee(with: event)
            }

            applyBand(from: anchor, to: point)
            updateAutoScroll(windowPoint: event.locationInWindow)

            // Recover if the button was released without us seeing the mouseUp.
            if NSEvent.pressedMouseButtons & 1 == 0 { forceFinish(cancelled: false) }
        }

        override func mouseUp(with event: NSEvent) {
            let didMarquee = isActive
            forceFinish(cancelled: false)
            anchorPoint = nil
            // Below the threshold this was a plain background click. Above it,
            // suppress the clear — same shape as `DraggableClickView`'s
            // `didStartDragSession` guard.
            if !didMarquee { onBackgroundClick?() }
        }

        // MARK: - Keyboard

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 53: // Escape
                if isActive {
                    forceFinish(cancelled: true)
                } else {
                    ShelfSelectionModel.shared.clear()
                }
            case 51, 117: // Delete, Forward Delete
                let items = ShelfSelectionModel.shared.selectedItems(in: ShelfStateViewModel.shared.items)
                guard !items.isEmpty else {
                    super.keyDown(with: event)
                    return
                }
                for item in items { ShelfActionService.remove(item) }
                ShelfSelectionModel.shared.clear()
            default:
                super.keyDown(with: event)
            }
        }

        /// Walks the whole view tree, so Cmd+A works even when this view isn't
        /// first responder (unlike `keyDown`).
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers == "a" else { return false }
            guard window != nil, !ShelfStateViewModel.shared.items.isEmpty else { return false }
            ShelfSelectionModel.shared.selectAll(in: ShelfStateViewModel.shared.items)
            return true
        }

        // MARK: - Lifecycle

        private func startMarquee(with event: NSEvent) {
            isActive = true
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let mode: ShelfSelectionModel.MarqueeMode =
                flags.contains(.command) ? .toggle :
                flags.contains(.shift) ? .union : .replace

            ShelfSelectionModel.shared.beginMarquee(mode: mode)
            onActiveChange?(true)
            installUpMonitorSafetyNet()
        }

        /// Idempotent teardown. Reached from the normal `mouseUp`, the safety-net
        /// monitor, and the view leaving its window.
        func forceFinish(cancelled: Bool) {
            removeUpMonitorSafetyNet()
            stopAutoScroll()

            guard isActive else {
                setRect(nil)
                return
            }
            isActive = false
            setRect(nil)

            if cancelled {
                ShelfSelectionModel.shared.cancelMarquee()
            } else {
                ShelfSelectionModel.shared.endMarquee()
            }
            onActiveChange?(false)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // If the notch closes mid-marquee this view leaves its window and
            // the mouseUp never lands, which would strand `isMarqueeSelecting`
            // at true and permanently break ShelfView's clear guard.
            if window == nil { forceFinish(cancelled: true) }
        }

        deinit {
            if let upMonitor { NSEvent.removeMonitor(upMonitor) }
            autoScrollTimer?.invalidate()
        }

        // MARK: - Safety net for a drag that ends outside the panel

        /// AppKit normally still delivers `mouseUp` to the view that got the
        /// `mouseDown`, even outside the window. This is a belt-and-braces
        /// backstop for the nonactivating-panel case. A local monitor suffices:
        /// while a button is held, the event stream stays with our app, so no
        /// global monitor (and no accessibility permission) is needed.
        private func installUpMonitorSafetyNet() {
            guard upMonitor == nil else { return }
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                self?.forceFinish(cancelled: false)
                return event
            }
        }

        private func removeUpMonitorSafetyNet() {
            if let upMonitor { NSEvent.removeMonitor(upMonitor) }
            upMonitor = nil
        }

        // MARK: - Auto-scroll

        /// The shelf is a single horizontal row, so the band routinely needs to
        /// reach items that are scrolled out of view.
        private func updateAutoScroll(windowPoint: NSPoint) {
            lastDragPointInWindow = windowPoint
            guard autoScrollTimer == nil else { return }

            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepAutoScroll() }
            }
            autoScrollTimer = timer
            // `.eventTracking` too, otherwise the timer stalls while the mouse
            // is held down.
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.add(timer, forMode: .eventTracking)
        }

        private func stopAutoScroll() {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }

        private func stepAutoScroll() {
            guard isActive,
                  let scrollView = enclosingScrollView,
                  let anchor = anchorPoint else { return }

            let clip = scrollView.contentView
            let pointInClip = clip.convert(lastDragPointInWindow, from: nil)

            var delta: CGFloat = 0
            if pointInClip.x < clip.bounds.minX + autoScrollEdge {
                delta = -min(autoScrollMaxStep, autoScrollEdge - (pointInClip.x - clip.bounds.minX))
            } else if pointInClip.x > clip.bounds.maxX - autoScrollEdge {
                delta = min(autoScrollMaxStep, autoScrollEdge - (clip.bounds.maxX - pointInClip.x))
            }
            guard delta != 0 else { return }

            let documentWidth = scrollView.documentView?.frame.width ?? 0
            let maxX = max(0, documentWidth - clip.bounds.width)
            let newX = min(max(0, clip.bounds.origin.x + delta), maxX)
            guard newX != clip.bounds.origin.x else { return }

            clip.scroll(to: NSPoint(x: newX, y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)

            // The cursor now sits over different content, so recompute the band
            // and its hits even though no mouseDragged arrived.
            applyBand(from: anchor, to: convert(lastDragPointInWindow, from: nil))
        }

        // MARK: - Selection

        private func applyBand(from anchor: NSPoint, to point: NSPoint) {
            let rect = NSRect(
                x: min(anchor.x, point.x),
                y: min(anchor.y, point.y),
                width: abs(point.x - anchor.x),
                height: abs(point.y - anchor.y)
            )
            setRect(rect)

            let hits = ShelfItemHitRegistry.shared
                .frames(in: self)
                .filter { NSIntersectsRect($0.frame, rect) }
                .map(\.id)
            ShelfSelectionModel.shared.updateMarquee(hitIDs: Set(hits))
        }

        // MARK: - Drawing

        private func setRect(_ rect: NSRect?) {
            guard rect != currentRect else { return }
            if let old = currentRect { setNeedsDisplay(old.insetBy(dx: -2, dy: -2)) }
            currentRect = rect
            if let new = rect { setNeedsDisplay(new.insetBy(dx: -2, dy: -2)) }
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let rect = currentRect, rect.width > 0 || rect.height > 0 else { return }

            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            path.fill()
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}
