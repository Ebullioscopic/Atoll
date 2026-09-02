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

struct ClipboardPopover: View {
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
            ClipboardPopoverHeader(
                selectedTab: $selectedTab,
                searchText: $searchText
            )
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Content
            if filteredItems.isEmpty {
                ClipboardPopoverEmptyState(
                    hasSearch: !searchText.isEmpty,
                    isHistoryTab: selectedTab == .history
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredItems) { item in
                            ClipboardPopoverItemRow(
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
        .frame(width: 280, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}

struct ClipboardPopoverHeader: View {
    @Binding var selectedTab: ClipboardTab
    @Binding var searchText: String
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Title
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .foregroundColor(.primary)
                    .font(.system(size: 14, weight: .medium))
                
                Text("Clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Clear button
                Button(action: {
                    if selectedTab == .history {
                        clipboardManager.clearHistory()
                    } else {
                        clipboardManager.clearPinnedItems()
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedTab == .history ? clipboardManager.clipboardHistory.isEmpty : clipboardManager.pinnedItems.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            
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
            .padding(.horizontal, 14)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 11))
                    .focused($isSearchFieldFocused)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 9))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 6)
    }
}

struct ClipboardPopoverEmptyState: View {
    let hasSearch: Bool
    let isHistoryTab: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasSearch ? "magnifyingglass" : (isHistoryTab ? "doc.on.clipboard" : "heart.fill"))
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            
            if hasSearch {
                Text("No results")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Try different search terms")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text(isHistoryTab ? "No clipboard history" : "No favorites")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(isHistoryTab ? "Copy something to start" : "Pin items to add favorites")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

struct ClipboardPopoverItemRow: View {
    let item: ClipboardItem
    let isHovered: Bool
    let isPinned: Bool
    let onHover: (UUID?) -> Void
    @ObservedObject var clipboardManager = ClipboardManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Type icon
            Image(systemName: item.type.icon)
                .font(.system(size: 12))
                .foregroundColor(.blue)
                .frame(width: 16)
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(item.type.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(timeAgoString(from: item.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons (shown on hover)
            if isHovered {
                HStack(spacing: 4) {
                    // Pin/Unpin button
                    Button(action: {
                        if isPinned {
                            clipboardManager.unpinItem(item)
                        } else {
                            clipboardManager.pinItem(item)
                        }
                    }) {
                        Image(systemName: isPinned ? "heart.fill" : "heart")
                            .font(.system(size: 9))
                            .foregroundColor(isPinned ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Copy button
                    Button(action: {
                        clipboardManager.copyToClipboard(item)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
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
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
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
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

#Preview {
    ClipboardPopover()
}
