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

import SwiftUI
import Defaults

struct ClipboardWindow: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var selectedTab: ClipboardTab = .history
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with tabs and search
            ClipboardWindowHeader(selectedTab: $selectedTab, searchText: $searchText)
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Content area
            ClipboardWindowContent(selectedTab: selectedTab, searchText: searchText)
        }
        .frame(width: 400, height: 300)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
    }
}

struct ClipboardWindowHeader: View {
    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String
    @ObservedObject var clipboardManager = ClipboardManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Title and controls
            HStack {
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
                        // Clear favorites
                        clipboardManager.clearPinnedItems()
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
            .padding(.vertical, 12)
            
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
            .padding(.bottom, 8)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search clipboard...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                
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
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

struct ClipboardWindowContent: View {
    let selectedTab: ClipboardTab
    let searchText: String
    @ObservedObject var clipboardManager = ClipboardManager.shared
    
    var filteredItems: [ClipboardItem] {
        let items = selectedTab == .history ? clipboardManager.regularHistory : clipboardManager.pinnedItems
        
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                item.preview.localizedCaseInsensitiveContains(searchText) ||
                item.type.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        if filteredItems.isEmpty {
            ClipboardEmptyState(tab: selectedTab, hasSearch: !searchText.isEmpty)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredItems) { item in
                        ClipboardWindowItemRow(item: item, tab: selectedTab)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct ClipboardEmptyState: View {
    let tab: ClipboardTab
    let hasSearch: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasSearch ? "magnifyingglass" : tab.icon)
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
                Text(tab == .history ? "No clipboard history" : "No favorites")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(tab == .history ? "Copy something to get started" : "Pin items from history to save them here")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardWindowItemRow: View {
    let item: ClipboardItem
    let tab: ClipboardTab
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var isHovering = false
    
    var isPinned: Bool {
        item.isPinned || clipboardManager.pinnedItems.contains(where: { $0.id == item.id })
    }
    
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
            if isHovering {
                HStack(spacing: 6) {
                    // Pin/Unpin button
                    Button(action: {
                        clipboardManager.togglePin(for: item)
                    }) {
                        Image(systemName: isPinned ? "heart.fill" : "heart")
                            .font(.system(size: 11))
                            .foregroundColor(isPinned ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Copy button
                    Button(action: {
                        clipboardManager.copyToClipboard(item)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
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
                .fill(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            clipboardManager.copyToClipboard(item)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    ClipboardWindow()
        .frame(width: 400, height: 300)
        .background(Color.gray.opacity(0.3))
}
