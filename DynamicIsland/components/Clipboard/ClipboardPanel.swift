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

private func applyClipboardCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

class ClipboardPanel: NSPanel {
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    // Override to allow the panel to become key window (required for TextField focus)
    override var canBecomeKey: Bool {
        return true
    }
    
    // Override to allow the panel to become main window (required for text input)
    override var canBecomeMain: Bool {
        return true
    }
    
    private func setupWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true  // Enable dragging
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true  // Mark as floating panel for proper behavior
        
        // Allow dragging from any part of the window
        styleMask.insert(.fullSizeContentView)
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary  // Float above full-screen apps
        ]

        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        
        // Accept mouse moved events for proper hover behavior
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let contentView = ClipboardPanelView {
            self.close()
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        applyClipboardCornerMask(hostingView, radius: 12)
        self.contentView = hostingView
        
        // Set initial size
        let preferredSize = CGSize(width: 320, height: 400)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionNearNotch() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Check if we have a saved position
        if let savedPosition = getSavedPosition() {
            // Validate saved position is still on screen
            let savedFrame = NSRect(origin: savedPosition, size: panelFrame.size)
            if screenFrame.intersects(savedFrame) {
                setFrameOrigin(savedPosition)
                return
            }
        }
        
        // Default to center of screen (not top center)
        let xPosition = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    private func getSavedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        let x = defaults.double(forKey: "clipboardPanelPositionX")
        let y = defaults.double(forKey: "clipboardPanelPositionY")
        
        // Check if we have valid saved coordinates (not default 0.0)
        if x != 0.0 || y != 0.0 {
            return NSPoint(x: x, y: y)
        }
        return nil
    }
    
    private func saveCurrentPosition() {
        let currentOrigin = frame.origin
        let defaults = UserDefaults.standard
        defaults.set(currentOrigin.x, forKey: "clipboardPanelPositionX")
        defaults.set(currentOrigin.y, forKey: "clipboardPanelPositionY")
    }
    
    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        // Save position whenever it changes (user dragging)
        saveCurrentPosition()
    }
    
    func positionNearMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let panelFrame = frame
        
        // Position near mouse but ensure it stays on screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        var xPosition = mouseLocation.x - panelFrame.width / 2
        var yPosition = mouseLocation.y - panelFrame.height - 20
        
        // Keep within screen bounds
        xPosition = max(screenFrame.minX + 10, min(xPosition, screenFrame.maxX - panelFrame.width - 10))
        yPosition = max(screenFrame.minY + 10, min(yPosition, screenFrame.maxY - panelFrame.height - 10))
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
}

struct ClipboardPanelView: View {
    let onClose: () -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var selectedTab: ClipboardTab = .history
    @State private var searchText = ""
    @State private var hoveredItemId: UUID?
    
    var filteredItems: [ClipboardItem] {
        let allItems = selectedTab == .history ? clipboardManager.regularHistory : clipboardManager.pinnedItems
        
        if searchText.isEmpty {
            return allItems
        } else {
            return allItems.filter { item in
                item.preview.localizedCaseInsensitiveContains(searchText) ||
                item.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            ClipboardPanelHeader(
                selectedTab: $selectedTab,
                searchText: $searchText,
                onClose: onClose
            )
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Content
            if filteredItems.isEmpty {
                ClipboardPanelEmptyState(
                    hasSearch: !searchText.isEmpty,
                    isHistoryTab: selectedTab == .history
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredItems) { item in
                            ClipboardPanelItemRow(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                isPinned: clipboardManager.pinnedItems.contains(where: { $0.id == item.id })
                            ) { hoverId in
                                hoveredItemId = hoverId
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}

struct ClipboardPanelHeader: View {
    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String
    let onClose: () -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Title and close button
            HStack {
                // Close button
                NativeStyleCloseButton(action: onClose)
                
                Image(systemName: "doc.on.clipboard")
                    .foregroundColor(.primary)
                    .font(.system(size: 16, weight: .medium))
                
                Text("Clipboard Manager")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Clear button
                Button(action: {
                    if selectedTab == .history {
                        clipboardManager.clearHistory()
                    } else {
                        clipboardManager.pinnedItems.removeAll()
                        clipboardManager.savePinnedItemsToDefaults()
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedTab == .history ? clipboardManager.clipboardHistory.isEmpty : clipboardManager.pinnedItems.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Tab selector
            HStack(spacing: 0) {
                ForEach(ClipboardTab.allCases, id: \.self) { tab in
                    ClipboardTabButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // Search bar (always visible)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                    .focused($isSearchFieldFocused)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }
}

struct ClipboardPanelEmptyState: View {
    let hasSearch: Bool
    let isHistoryTab: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasSearch ? "magnifyingglass" : (isHistoryTab ? "doc.on.clipboard" : "heart.fill"))
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            if hasSearch {
                Text("No results found")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Try adjusting your search terms")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                Text(isHistoryTab ? "No clipboard history" : "No favorites")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(isHistoryTab ? "Copy something to get started" : "Pin items to add them to favorites")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardPanelItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isPinned: Bool
    let onHover: (UUID?) -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var justCopied = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Type icon
            Image(systemName: item.type.icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(item.type.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(timeAgoString(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 6) {
                    // Pin/Unpin button
                    Button(action: {
                        if isPinned {
                            clipboardManager.unpinItem(item)
                        } else {
                            clipboardManager.pinItem(item)
                        }
                    }) {
                        Image(systemName: isPinned ? "heart.fill" : "heart")
                            .font(.system(size: 11))
                            .foregroundColor(isPinned ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Copy button
                    Button(action: {
                        clipboardManager.copyToClipboard(item)
                        
                        withAnimation(.easeInOut(duration: 0.2)) {
                            justCopied = true
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                justCopied = false
                            }
                        }
                    }) {
                        Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(justCopied ? .green : .green)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Delete button
                    Button(action: {
                        if isPinned {
                            clipboardManager.unpinItem(item)
                        } else {
                            clipboardManager.deleteItem(item)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                onHover(hovering ? item.id : nil)
            }
        }
        .onTapGesture {
            clipboardManager.copyToClipboard(item)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(localized: "\(minutes)m ago")
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(localized: "\(hours)h ago")
        } else {
            let days = Int(interval / 86400)
            return String(localized: "\(days)d ago")
        }
    }
}

#Preview {
    ClipboardPanelView {
        print("Close panel")
    }
}
