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

import Foundation
import Combine

private let _shelfTypeAnchor: Bool = {
    _ = String(describing: ShelfItem.self)
    return true
}()

@MainActor
final class ShelfSelectionModel: ObservableObject {
    static let shared = ShelfSelectionModel()

    @Published private(set) var selectedIDs: Set<UUID> = []

    // Anchor for shift-range selection
    private var lastAnchorID: UUID? = nil

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    var firstSelectedItem: ShelfItem? {
        guard let firstID = selectedIDs.first else { return nil }
        return ShelfStateViewModel.shared.items.first(where: { $0.id == firstID })
    }

    func selectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    func selectSingle(_ item: ShelfItem) {
        selectedIDs = [item.id]
        lastAnchorID = item.id
    }

    func toggle(_ item: ShelfItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
        lastAnchorID = item.id
    }

    func shiftSelect(to item: ShelfItem, in allItems: [ShelfItem]) {
        // Determine anchor
        let anchorID = lastAnchorID ?? selectedIDs.first ?? item.id
        guard let startIndex = allItems.firstIndex(where: { $0.id == anchorID }),
              let endIndex = allItems.firstIndex(where: { $0.id == item.id }) else {
            // Fallback to single select if indices not found
            return selectSingle(item)
        }
        let lower = min(startIndex, endIndex)
        let upper = max(startIndex, endIndex)
        let rangeIDs = allItems[lower...upper].map { $0.id }
        selectedIDs = Set(rangeIDs)
    }

    func clear() {
        selectedIDs.removeAll()
        lastAnchorID = nil
    }

    func selectAll(in allItems: [ShelfItem]) {
        let all = Set(allItems.map(\.id))
        if selectedIDs != all { selectedIDs = all }
        if let anchor = lastAnchorID, all.contains(anchor) { return }
        lastAnchorID = allItems.first?.id
    }

    func reconcileSelection(with allItems: [ShelfItem]) {
        let validIDs = Set(allItems.map(\.id))
        let filteredSelection = selectedIDs.intersection(validIDs)

        if filteredSelection != selectedIDs {
            selectedIDs = filteredSelection
        }

        if let anchor = lastAnchorID, !validIDs.contains(anchor) {
            lastAnchorID = selectedIDs.first
        }

        // An item removed mid-marquee would otherwise linger in the base set and
        // get re-added by the next `updateMarquee`, or come back as part of the
        // selection `cancelMarquee` restores.
        marqueeBaseSelection.formIntersection(validIDs)
        marqueePreviousSelection.formIntersection(validIDs)
        if let first = marqueeFirstHitID, !validIDs.contains(first) {
            marqueeFirstHitID = nil
        }
    }

    // Keep anchor sane if items array changed drastically (optional helper)
    func ensureValidAnchor(in allItems: [ShelfItem]) {
        if let anchor = lastAnchorID, !allItems.contains(where: { $0.id == anchor }) {
            lastAnchorID = selectedIDs.first
        }
    }

    @Published private(set) var isDragging: Bool = false

    func beginDrag() {
        isDragging = true
    }

    func endDrag() {
        isDragging = false
    }

    // MARK: - Marquee (rubber-band) selection

    /// A rubber-band selection is in progress. Deliberately separate from
    /// `isDragging`, which means "an NSDraggingSession is carrying items out of
    /// the shelf" and gates `ShelfView.handleDrop`. Conflating the two would
    /// make `.onDrop` silently reject drops while the band is up.
    @Published private(set) var isMarqueeSelecting: Bool = false

    enum MarqueeMode {
        case replace   // no modifier
        case union     // Shift
        case toggle    // Command
    }

    /// What `updateMarquee` unions/toggles the hit set against — empty in
    /// `.replace` mode, since the band there defines the whole selection.
    private var marqueeBaseSelection: Set<UUID> = []
    /// What was selected before the band started. Distinct from the base set,
    /// which `.replace` deliberately empties, and which therefore cannot serve
    /// as the thing `cancelMarquee` restores.
    private var marqueePreviousSelection: Set<UUID> = []
    private var marqueeMode: MarqueeMode = .replace
    private var marqueeFirstHitID: UUID?

    func beginMarquee(mode: MarqueeMode) {
        isMarqueeSelecting = true
        marqueeMode = mode
        marqueeFirstHitID = nil
        marqueePreviousSelection = selectedIDs
        marqueeBaseSelection = (mode == .replace) ? [] : selectedIDs
        if mode == .replace && !selectedIDs.isEmpty {
            selectedIDs = []
        }
    }

    func updateMarquee(hitIDs: Set<UUID>) {
        guard isMarqueeSelecting else { return }
        if marqueeFirstHitID == nil { marqueeFirstHitID = hitIDs.first }

        let next: Set<UUID>
        switch marqueeMode {
        case .replace, .union:
            next = marqueeBaseSelection.union(hitIDs)
        case .toggle:
            next = marqueeBaseSelection.symmetricDifference(hitIDs)
        }

        // Publishing redraws every ShelfItemView; this runs on every mouse-moved
        // event, so only write when the set actually changed.
        guard next != selectedIDs else { return }
        selectedIDs = next
    }

    func endMarquee() {
        guard isMarqueeSelecting else { return }
        isMarqueeSelecting = false
        marqueeBaseSelection = []
        marqueePreviousSelection = []
        // Anchor a following Shift-click somewhere sensible.
        if let first = marqueeFirstHitID, selectedIDs.contains(first) {
            lastAnchorID = first
        } else if let anchor = lastAnchorID, selectedIDs.contains(anchor) {
            // keep it
        } else {
            lastAnchorID = selectedIDs.first
        }
        marqueeFirstHitID = nil
    }

    /// Escape, or the view being torn down mid-drag: restore what was selected
    /// before the band started.
    func cancelMarquee() {
        guard isMarqueeSelecting else { return }
        isMarqueeSelecting = false
        if selectedIDs != marqueePreviousSelection { selectedIDs = marqueePreviousSelection }
        marqueeBaseSelection = []
        marqueePreviousSelection = []
        marqueeFirstHitID = nil
    }
}
