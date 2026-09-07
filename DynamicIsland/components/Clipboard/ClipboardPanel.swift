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
        applyClipboardCornerMask(hostingView, radius: ClipboardPanelMetrics.cornerRadius)
        self.contentView = hostingView
        
        // Set initial size
        let preferredSize = ClipboardPanelMetrics.panelSize
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionNearNotch() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Check if we have a saved position
        if let savedPosition = getSavedPosition() {
            let savedFrame = NSRect(origin: savedPosition, size: panelFrame.size)
            if screenFrame.contains(savedFrame) {
                setFrameOrigin(savedPosition)
                return
            }
            // Merely intersecting is not enough: a position saved when the
            // panel was narrower can now hang off the edge. Nudge it back
            // inside rather than throwing the user's placement away.
            if screenFrame.intersects(savedFrame) {
                setFrameOrigin(
                    ClipboardPanel.clampedOrigin(savedPosition, size: panelFrame.size, within: screenFrame)
                )
                return
            }
        }
        
        // Default to center of screen (not top center)
        let xPosition = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    /// Keeps a frame of `size` fully inside `bounds`, pinning to the origin
    /// edges if the panel is somehow larger than the visible frame.
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, within bounds: NSRect) -> NSPoint {
        let maxX = max(bounds.minX, bounds.maxX - size.width)
        let maxY = max(bounds.minY, bounds.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, bounds.minX), maxX),
            y: min(max(origin.y, bounds.minY), maxY)
        )
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

enum ClipboardPanelMetrics {
    static let panelSize = CGSize(width: 380, height: 480)
    static let cornerRadius: CGFloat = 18
    static let rowCornerRadius: CGFloat = 12
    static let contentInset: CGFloat = 12
}

/// Muted per-type tints. Saturated primaries on every row read as noise; these
/// sit far enough apart to scan by colour without shouting.
private extension ClipboardItemType {
    var tint: Color {
        switch self {
        case .text: return Color(red: 0.55, green: 0.58, blue: 0.64)
        case .url: return Color(red: 0.35, green: 0.56, blue: 0.92)
        case .file: return Color(red: 0.92, green: 0.66, blue: 0.30)
        case .image: return Color(red: 0.66, green: 0.48, blue: 0.90)
        case .rtf: return Color(red: 0.36, green: 0.72, blue: 0.62)
        case .unknown: return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
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
        VStack(spacing: 10) {
            ClipboardPanelHeader(
                selectedTab: $selectedTab,
                searchText: $searchText,
                onClose: onClose
            )

            if filteredItems.isEmpty {
                ClipboardPanelEmptyState(
                    hasSearch: !searchText.isEmpty,
                    isHistoryTab: selectedTab == .history
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
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
                    .padding(.horizontal, ClipboardPanelMetrics.contentInset)
                    .padding(.bottom, ClipboardPanelMetrics.contentInset)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: ClipboardPanelMetrics.panelSize.width, height: ClipboardPanelMetrics.panelSize.height)
        .background {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay {
                    // Lifts the material away from flat grey and gives the panel
                    // a light source, the way macOS window chrome reads.
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: ClipboardPanelMetrics.cornerRadius, style: .continuous))
        .overlay {
            // Hairline keeps the edge legible against light wallpapers.
            RoundedRectangle(cornerRadius: ClipboardPanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 26, x: 0, y: 12)
        .animation(.easeOut(duration: 0.18), value: filteredItems.count)
    }
}

struct ClipboardPanelHeader: View {
    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String
    let onClose: () -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isSearchHovered = false
    @State private var isClearHovered = false

    private var canClear: Bool {
        selectedTab == .history ? !clipboardManager.regularHistory.isEmpty : !clipboardManager.pinnedItems.isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            // Search carries the window's identity, so there is no separate
            // title bar competing for the 480pt of height.
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("Search clipboard", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($isSearchFieldFocused)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(isSearchFieldFocused ? 0.12 : (isSearchHovered ? 0.09 : 0.07)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isSearchFieldFocused ? 0.65 : 0), lineWidth: 1.5)
                }
                .onHover { isSearchHovered = $0 }
                .animation(.easeOut(duration: 0.16), value: isSearchFieldFocused)
                .animation(.easeOut(duration: 0.16), value: searchText.isEmpty)

                NativeStyleCloseButton(action: onClose)
            }

            HStack(spacing: 8) {
                ClipboardSegmentedTabs(selectedTab: $selectedTab)

                Spacer(minLength: 0)

                Button {
                    if selectedTab == .history {
                        clipboardManager.clearHistory()
                    } else {
                        clipboardManager.clearPinnedItems()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .medium))
                        // Red only once you are actually on it — a permanently
                        // red destructive glyph pulls the eye off the content.
                        .foregroundStyle(isClearHovered && canClear ? Color.red : Color.secondary)
                        .frame(width: 26, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(isClearHovered && canClear ? 0.1 : 0))
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canClear)
                .opacity(canClear ? 1 : 0.35)
                .onHover { isClearHovered = $0 }
                .animation(.easeOut(duration: 0.16), value: isClearHovered)
                .help(selectedTab == .history ? "Clear history" : "Clear favorites")
            }
        }
        .padding(.horizontal, ClipboardPanelMetrics.contentInset)
        .padding(.top, ClipboardPanelMetrics.contentInset)
    }
}

/// Sliding segmented control — the selection is one shape that moves, rather
/// than a filled blue rectangle appearing and disappearing under each tab.
struct ClipboardSegmentedTabs: View {
    @Binding var selectedTab: ClipboardTab
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Namespace private var selectionNamespace

    private func count(for tab: ClipboardTab) -> Int {
        switch tab {
        case .history: return clipboardManager.regularHistory.count
        case .favorites: return clipboardManager.pinnedItems.count
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))

                        Text(tab.localizedName)
                            .font(.system(size: 11.5, weight: .medium))

                        if count(for: tab) > 0 {
                            Text("\(count(for: tab))")
                                .font(.system(size: 9.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.7))
                        }
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.14))
                                .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }
}

struct ClipboardPanelEmptyState: View {
    let hasSearch: Bool
    let isHistoryTab: Bool

    private var icon: String {
        hasSearch ? "magnifyingglass" : (isHistoryTab ? "doc.on.clipboard" : "heart")
    }

    private var title: String {
        if hasSearch { return String(localized: "No results") }
        return isHistoryTab ? String(localized: "No clipboard history") : String(localized: "No favorites")
    }

    private var subtitle: String {
        if hasSearch { return String(localized: "Try a different search term") }
        return isHistoryTab
            ? String(localized: "Copy something to get started")
            : String(localized: "Pin items to keep them here")
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, height: 56)
            .padding(.bottom, 14)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

struct ClipboardPanelItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isPinned: Bool
    let onHover: (UUID?) -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var justCopied = false
    @State private var copyResetWorkItem: DispatchWorkItem?

    private var thumbnail: NSImage? {
        guard item.type == .image, let data = item.getImageData() else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            leadingBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text(item.type.displayName)
                        .foregroundStyle(item.type.tint.opacity(0.95))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(timeAgoString(from: item.timestamp))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10.5, weight: .medium))
            }

            Spacer(minLength: 4)

            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: ClipboardPanelMetrics.rowCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ClipboardPanelMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.08 : 0), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: ClipboardPanelMetrics.rowCornerRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                onHover(hovering ? item.id : nil)
            }
        }
        .onTapGesture {
            copy()
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        ZStack {
            if let thumbnail {
                // An actual preview beats a generic photo glyph for images.
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                item.type.tint.opacity(0.18)
                Image(systemName: justCopied ? "checkmark" : item.type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(justCopied ? Color.green : item.type.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var actions: some View {
        // Reserved width: the buttons fade in rather than appearing and
        // shoving the text sideways on every hover.
        HStack(spacing: 2) {
            ClipboardRowActionButton(
                icon: isPinned ? "pin.fill" : "pin",
                tint: isPinned ? Color.accentColor : nil,
                help: isPinned ? "Unpin" : "Pin"
            ) {
                if isPinned {
                    clipboardManager.unpinItem(item)
                } else {
                    clipboardManager.pinItem(item)
                }
            }
            // A pinned row keeps its marker visible so the state is readable
            // without hovering every row to find it.
            .opacity(isHovered || isPinned ? 1 : 0)

            ClipboardRowActionButton(
                icon: justCopied ? "checkmark" : "doc.on.doc",
                tint: justCopied ? Color.green : nil,
                help: "Copy"
            ) {
                copy()
            }
            .opacity(isHovered ? 1 : 0)

            ClipboardRowActionButton(icon: "trash", tint: nil, hoverTint: .red, help: "Delete") {
                if isPinned {
                    clipboardManager.unpinItem(item)
                } else {
                    clipboardManager.deleteItem(item)
                }
            }
            .opacity(isHovered ? 1 : 0)
        }
        .frame(width: 78, alignment: .trailing)
    }

    private func copy() {
        clipboardManager.copyToClipboard(item)

        withAnimation(.easeOut(duration: 0.18)) {
            justCopied = true
        }

        // Copying the same row again restarts the confirmation: without
        // cancelling, the first timer clears the checkmark 1.5s after the
        // *first* press, cutting the second one short.
        copyResetWorkItem?.cancel()
        let reset = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                justCopied = false
            }
        }
        copyResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
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

private struct ClipboardRowActionButton: View {
    let icon: String
    var tint: Color? = nil
    var hoverTint: Color? = nil
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(resolvedTint)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help(help)
    }

    private var resolvedTint: Color {
        if let tint { return tint }
        if isHovered, let hoverTint { return hoverTint }
        return .secondary
    }
}

#Preview {
    ClipboardPanelView {
        print("Close panel")
    }
}
