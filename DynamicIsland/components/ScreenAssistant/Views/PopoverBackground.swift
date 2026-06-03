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

// MARK: - Screenshot Popover Background (Hidden from Screen Recording)
struct ScreenshotPopoverBackground: NSViewRepresentable {
    // Coordinator retains the NSWindow reference used for registration so
    // that dismantleNSView can unregister even if nsView.window is nil.
    class Coordinator {
        weak var registeredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.registeredWindow = window
            ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            context.coordinator.registeredWindow = window
            ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        // Prefer the coordinator's retained window reference; fall back to
        // nsView.window in case the view is still attached.
        let window = coordinator.registeredWindow ?? nsView.window
        if let window = window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
        coordinator.registeredWindow = nil
    }
}
