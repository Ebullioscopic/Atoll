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

import Cocoa

class StatusBarMenu: NSMenu {
    
    var statusItem: NSStatusItem!
    
    override init(title: String) {
        super.init(title: title)
        setupStatusItem()
    }
    
    convenience init() {
        self.init(title: "DynamicIsland")
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        // Initialize the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set the menu bar icon
        if let button = statusItem.button {
            button.image = NSImage(named: "logo")
        }
        
        // Set up the menu
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        self.addItem(settingsItem)
        self.addItem(.separator())
        self.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = self
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

}
