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
import Defaults

class ScreenAssistantPanelManager: ObservableObject {
    static let shared = ScreenAssistantPanelManager()
    
    // Backward compatibility wrapper - delegates to the new ScreenAssistantManager
    private var screenAssistantPanel: ScreenAssistantPanel?
    
    private init() {}
    
    func showScreenAssistantPanel() {
        hideScreenAssistantPanel() // Close any existing panel
        
        // Use the new dual-panel system
        ScreenAssistantManager.shared.showPanels()
        
        // Create a dummy panel for backward compatibility
        let panel = ScreenAssistantPanel()
        self.screenAssistantPanel = panel
        
        // The actual panels are managed by ScreenAssistantManager
        // This is just for compatibility with existing code
        
        print("ScreenAssistant: New dual-panel system activated")
    }
    
    func hideScreenAssistantPanel() {
        // Close the new panel system
        ScreenAssistantManager.shared.closePanels()
        
        // Clean up compatibility panel
        screenAssistantPanel?.close()
        screenAssistantPanel = nil
        
        print("ScreenAssistant: Panels hidden")
    }
    
    func toggleScreenAssistantPanel() {
        if ScreenAssistantManager.shared.arePanelsVisible() {
            hideScreenAssistantPanel()
        } else {
            showScreenAssistantPanel()
        }
    }
    
    var isPanelVisible: Bool {
        return ScreenAssistantManager.shared.arePanelsVisible()
    }
}
