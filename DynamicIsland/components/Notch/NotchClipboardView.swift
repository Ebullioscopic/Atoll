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
import AppKit
import Defaults

/// Clipboard as a card grid, each card draggable out to other apps, tap to copy,
/// hover to delete. Used both as the dedicated `.notchTab` view and, at a smaller
/// `minCardWidth`, as the clipboard panel in `.separateTab` split mode. The adaptive
/// grid fills whatever width it is given (more columns in the full notch tab, fewer
/// in the narrow split panel).
struct NotchClipboardView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @State private var hoveredItemId: UUID?
    @State private var justCopiedId: UUID?
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false
    @State private var showClearHistoryAlert = false
    @State private var autoCloseToken = UUID()

    /// Minimum card width; drives how many columns the adaptive grid shows.
    var minCardWidth: CGFloat = 200
    /// Force an exact column count (used by the narrow `.separateTab` panel, where an
    /// adaptive minimum would collapse to a single column). nil = adaptive by width.
    var fixedColumns: Int? = nil

    private var columns: [GridItem] {
        if let n = fixedColumns {
            return Array(repeating: GridItem(.flexible(), spacing: 8), count: max(1, n))
        }
        return [GridItem(.adaptive(minimum: minCardWidth, maximum: .infinity), spacing: 8)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if clipboardManager.clipboardHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(clipboardManager.clipboardHistory) { item in
                            ClipboardGridCard(
                                item: item,
                                isHovered: hoveredItemId == item.id,
                                justCopied: justCopiedId == item.id,
                                onDelete: { clipboardManager.deleteItem(item) }
                            )
                            .contentShape(Rectangle())
                            .clipboardDraggable(item)
                            .onHover { hovering in
                                // Only clear on exit if the id still refers to this card:
                                // entering the next card can fire `true` before this card's
                                // `false`, and an unconditional nil would wipe that entry.
                                if hovering { hoveredItemId = item.id }
                                else if hoveredItemId == item.id { hoveredItemId = nil }
                            }
                            .onTapGesture { copy(item) }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(item.type.displayName): \(item.preview)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { copy(item) }
                            .accessibilityAction(named: Text("Delete")) { clipboardManager.deleteItem(item) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { updateSuppression(for: $0) }
        .onDisappear {
            updateSuppression(for: false)
            // Release the alert-driven suppression too: if the view is torn down while
            // the clear-history alert is open, onChange never fires false and it leaks.
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
        }
        .alert("Clear Clipboard History?", isPresented: $showClearHistoryAlert) {
            Button("Clear History", role: .destructive) { clipboardManager.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved clipboard item from the notch tab.")
        }
        .onChange(of: showClearHistoryAlert) { _, isShowing in
            vm.setAutoCloseSuppression(isShowing, token: autoCloseToken)
        }
        .onAppear {
            if Defaults[.enableClipboardManager], !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Clipboard")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            if !clipboardManager.clipboardHistory.isEmpty {
                Button(action: { showClearHistoryAlert = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 16, height: 16)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No copies yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Copy something to see it here")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    private func copy(_ item: ClipboardItem) {
        clipboardManager.copyToClipboard(item)
        withAnimation { justCopiedId = item.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if justCopiedId == item.id {
                withAnimation { justCopiedId = nil }
            }
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

/// One clipboard entry as a compact card: thumbnail/type icon, preview, meta,
/// and a hover-revealed delete button in the top-trailing corner.
struct ClipboardGridCard: View {
    let item: ClipboardItem
    let isHovered: Bool
    let justCopied: Bool
    let onDelete: () -> Void

    // Decode the image once per item instead of on every render. `body` re-runs for hover
    // and copy-feedback changes, and decoding the on-disk PNG on the main thread each time
    // is wasteful; `.task(id:)` loads it once and refreshes only when the item changes.
    @State private var cachedImage: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.type.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(timeAgoString(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovered ? 0.12 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete this item")
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .task(id: item.id) {
            cachedImage = item.type == .image
                ? item.getImageData().flatMap(NSImage.init(data:))
                : nil
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.type == .image, let nsImage = cachedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                .overlay {
                    // Copy confirmation for image cards (the icon cards swap to a checkmark;
                    // image cards keep their thumbnail, so badge the checkmark on top).
                    if justCopied {
                        RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.5))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                    }
                }
        } else {
            Image(systemName: justCopied ? "checkmark.circle.fill" : item.type.icon)
                .font(.system(size: 16))
                .foregroundColor(justCopied ? .green : .blue)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "Just now") }
        if interval < 3600 { return String(localized: "\(Int(interval/60))m") }
        return String(localized: "\(Int(interval/3600))h")
    }
}
