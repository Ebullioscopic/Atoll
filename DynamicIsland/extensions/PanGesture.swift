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

enum PanDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
    var sign: CGFloat { (self == .right || self == .down) ? 1 : -1 }

    func signed(from translation: CGSize) -> CGFloat { (isHorizontal ? translation.width : translation.height) * sign }
    func signed(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat { (isHorizontal ? deltaX : deltaY) * sign }
}

extension View {
    func panGesture(direction: PanDirection, threshold: CGFloat = 4, action: @escaping (CGFloat, NSEvent.Phase) -> Void) -> some View {
        self
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let s = direction.signed(from: value.translation)
                        guard s > 0, s.magnitude >= threshold else { return }
                        action(s.magnitude, .changed)
                    }
                    .onEnded { _ in action(0, .ended) }
            )
            .background(ScrollMonitor(direction: direction, threshold: threshold, action: action))
    }
}

private struct ScrollMonitor: NSViewRepresentable {
    let direction: PanDirection
    let threshold: CGFloat
    let action: (CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor(on: view)
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.removeMonitor() }

    func makeCoordinator() -> Coordinator { 
        Coordinator(direction: direction, threshold: threshold, action: action) 
    }

    @MainActor final class Coordinator: NSObject {
        private let direction: PanDirection
        private let threshold: CGFloat
        private let action: (CGFloat, NSEvent.Phase) -> Void
        private var monitor: Any?
        private var globalMonitor: Any?
        private var accumulated: CGFloat = 0
        private var active = false
        private let noiseThreshold: CGFloat = 0.2
        private weak var observedView: NSView?
        /// Small vertical inset so scroll gestures fire when the cursor
        /// "kisses" the very top of the screen inside the physical notch
        /// area. Kept at zero horizontally to avoid unwanted hover opens
        /// from the sides.
        private let verticalEdgeInset: CGFloat = 4
        private var lastEventTimestamp: TimeInterval = 0

        init(direction: PanDirection, threshold: CGFloat, action: @escaping (CGFloat, NSEvent.Phase) -> Void) {
            self.direction = direction
            self.threshold = threshold
            self.action = action
        }

        func installMonitor(on view: NSView) {
            removeMonitor()
            observedView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self else { return event }
                self.handleScroll(event)
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                self?.handleScroll(event)
            }
        }

        func removeMonitor() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            if let globalMonitor = globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
            accumulated = 0
            active = false
            observedView = nil
            lastEventTimestamp = 0
        }

        private func handleScroll(_ event: NSEvent) {
            guard lastEventTimestamp != event.timestamp else { return }
            lastEventTimestamp = event.timestamp
            guard isCursorNearObservedView(using: event) else { return }

            if event.phase == .ended || event.momentumPhase == .ended {
                if active {
                    action(accumulated.magnitude, .ended)
                } else {
                    action(0, .ended)
                }
                active = false
                accumulated = 0
                return
            }

            // Momentum is the tail of a flick the user has already let go of, not
            // new input. A trackpad delivers a swipe as a run of touch events and
            // then a run of momentum ones, and the gesture ends between the two --
            // so the momentum was accumulating from zero against the same
            // threshold the touch had just crossed, firing the action a second
            // time. One swipe skipped two tracks.
            //
            // Discrete gestures read the touch, not the coast. The cost is that a
            // very light flick that only used to reach the threshold once momentum
            // carried it now needs a slightly longer swipe.
            guard event.momentumPhase.isEmpty else { return }

            let s = direction.signed(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
            guard s.magnitude > noiseThreshold else { return }
            accumulated = s > 0 ? accumulated + s : 0

            if !active && accumulated >= threshold {
                active = true
                action(accumulated.magnitude, .began)
            } else if active {
                action(accumulated.magnitude, .changed)
            }
        }

        private func isCursorNearObservedView(using event: NSEvent) -> Bool {
            guard let view = observedView, let window = view.window else { return false }

            let screenPoint: NSPoint
            if let eventWindow = event.window {
                let rect = NSRect(origin: event.locationInWindow, size: .zero)
                screenPoint = eventWindow.convertToScreen(rect).origin
            } else {
                screenPoint = NSEvent.mouseLocation
            }

            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let localPoint = view.convert(windowPoint, from: nil)

            // Extend the hit area vertically by a few points so the cursor
            // at the very top screen edge (kissing the notch) still triggers
            // scroll gestures. No horizontal extension to prevent false opens
            // from the sides of the notch.
            let hitArea = view.bounds.insetBy(dx: 0, dy: -verticalEdgeInset)
            return hitArea.contains(localPoint)
        }
    }
}
