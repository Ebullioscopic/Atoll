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
import Defaults
import Foundation
import SwiftUI

/// The size the open notch's content wants for a given tab.
///
/// Three places need this number and used to work it out separately: the
/// SwiftUI content frame in ``ContentView``, the `NSWindow` in
/// ``AppDelegate``, and ``DynamicIslandViewModel/notchSize``, which
/// ``NotchTimerView`` and the calendar measure their own content against.
///
/// They agreed only for as long as every tab wanted the same height. Each tab
/// that asked for its own was taught to them one at a time, and the ones that
/// were missed drifted: the view model never learned the timer or the terminal,
/// so on the timer tab the window stood at 250pt while `notchSize` stayed at
/// 200 and the tab sized its controls against 132pt of content space inside
/// 218pt of notch -- a band of empty notch under the controls.
///
/// Resolving the height here means a new tab height is added once rather than
/// three times, and cannot be added to two places out of three.
///
/// Scope: this answers for the *open* notch's tab content only. Each caller
/// keeps its own handling of the closed-notch surfaces -- sneak peek, the
/// recording HUD, the battery HUD -- because those differ per caller by
/// design, and its own outer padding.
@MainActor
func notchTabContentSize(
    from baseSize: CGSize,
    view: NotchViews,
    isNotchOpen: Bool,
    statsSecondRowProgress: CGFloat
) -> CGSize {
    var size = baseSize

    switch view {
    case .timer:
        size.height = 250 // Extra space for timer presets
    case .notes:
        size.height = max(size.height, DynamicIslandViewCoordinator.shared.notesLayoutState.preferredHeight)
    case .clipboard:
        // Clipboard has its own fixed height source; don't inherit whatever
        // notes layout state happens to be set.
        size.height = max(size.height, NotesLayoutState.list.preferredHeight)
    case .terminal:
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxFraction = Defaults[.terminalMaxHeightFraction]
        size.height = min(screenHeight * maxFraction, max(300, screenHeight * maxFraction))
    case .llmUsage:
        size.height = max(size.height, llmUsageOpenNotchHeight)
    case .extensionExperience:
        if let preferred = extensionTabPreferredHeight(baseSize: baseSize) {
            size.height = preferred
        }
    case .home:
        if Defaults[.enableMinimalisticUI],
           let preferred = extensionMinimalisticPreferredHeight(baseSize: baseSize) {
            size.height = preferred
        } else if isNotchOpen, standaloneCalendarActive() {
            // Gated on the open state: a closed notch draws nothing that needs
            // the month's height, and sizing the window for it would leave a
            // tall transparent slab over the top of the screen while the notch
            // is a sliver. Opening does not depend on this -- the view model
            // computes the expanded target and applies it before it sets
            // `notchState`.
            size.height = max(size.height, Defaults[.calendarViewMode].notchHeight)
        }
    case .shelf, .stats, .colorPicker:
        break
    }

    // Both of these no-op unless their own tab is the active one, so applying
    // them to every tab is the same as the per-tab returns they replaced.
    size = inlineLyricsAdjustedNotchSize(
        from: size,
        isHomeTabActive: view == .home && isNotchOpen
    )

    return statsAdjustedNotchSize(
        from: size,
        isStatsTabActive: view == .stats,
        secondRowProgress: statsSecondRowProgress
    )
}

@MainActor
func extensionTabPreferredHeight(baseSize: CGSize) -> CGFloat? {
    guard let preferred = currentExtensionTabPayload()?.descriptor.tab?.preferredHeight else {
        return nil
    }
    let minHeight = baseSize.height
    let maxHeight = baseSize.height + statsAdditionalRowHeight
    return min(max(preferred, minHeight), maxHeight)
}

@MainActor
func extensionMinimalisticPreferredHeight(baseSize: CGSize) -> CGFloat? {
    guard let configuration = ExtensionNotchExperienceManager.shared.minimalisticReplacementPayload()?.descriptor.minimalistic else {
        return nil
    }

    let minHeight = baseSize.height
    let maxHeight = baseSize.height + statsAdditionalRowHeight

    var contentHeight: CGFloat = 0
    var blockCount = 0

    if configuration.headline != nil {
        contentHeight += 24
        blockCount += 1
    }

    if configuration.subtitle != nil {
        contentHeight += 20
        blockCount += 1
    }

    if !configuration.sections.isEmpty {
        let sectionEstimate: CGFloat = 98
        contentHeight += CGFloat(configuration.sections.count) * sectionEstimate
        blockCount += configuration.sections.count
    }

    if let webDescriptor = configuration.webContent {
        contentHeight += webDescriptor.preferredHeight
        blockCount += 1
    }

    guard blockCount > 0 else { return nil }

    let spacingAllowance = CGFloat(max(blockCount - 1, 0)) * 16
    let topPadding: CGFloat = 10
    let bottomPadding: CGFloat = configuration.webContent == nil ? 10 : 0
    let estimatedHeight = contentHeight + spacingAllowance + topPadding + bottomPadding

    let clampedHeight = min(max(estimatedHeight, minHeight), maxHeight)
    return clampedHeight > minHeight ? clampedHeight : nil
}

@MainActor
func currentExtensionTabPayload() -> ExtensionNotchExperiencePayload? {
    guard Defaults[.enableThirdPartyExtensions],
          Defaults[.enableExtensionNotchExperiences],
          Defaults[.enableExtensionNotchTabs] else {
        return nil
    }
    if let selectedID = DynamicIslandViewCoordinator.shared.selectedExtensionExperienceID,
       let payload = ExtensionNotchExperienceManager.shared.payload(experienceID: selectedID) {
        return payload
    }
    return ExtensionNotchExperienceManager.shared.highestPriorityTabPayload()
}
