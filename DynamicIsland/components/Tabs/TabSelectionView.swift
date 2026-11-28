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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    // Observed so the tab list refreshes when the Home tab's content toggles change.
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.tabBarPosition) private var tabBarPosition
    @Default(.tabSwitchOnHover) private var tabSwitchOnHover
    @Default(.enableGestures) private var enableGestures
    @Default(.swipeBetweenTabs) private var swipeBetweenTabs
    @Default(.gestureSensitivity) private var gestureSensitivity
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Namespace var animation

    /// Which tab the pointer is currently resting on, when hover switching is on.
    @State private var hoveredTabID: String?

    /// Whether hover switching may act yet. The tab bar is built when the notch
    /// opens, and the notch opens under a pointer that is already sitting there,
    /// so the first hover it reports belongs to the pointer that opened the notch
    /// rather than to a choice. Acting on that switches tabs on its own.
    @State private var hoverArmed = false

    /// Long enough that a pointer crossing the rail on its way elsewhere does not
    /// drag the selection with it, short enough that a deliberate hover still
    /// feels immediate.
    private let hoverDwell = Duration.milliseconds(150)

    /// Time the notch is given to finish opening before a hover counts as intent.
    private let hoverArmingDelay = Duration.milliseconds(500)

    /// A swipe moves one tab per gesture; set once it has, cleared when the fingers lift.
    @State private var swipeHandled = false

    /// The tab step a swipe asked for, applied in `onChange` so it reads the current tabs.
    @State private var requestedSwipeStep: Int?
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if coordinator.availableStandardTabs.contains(.home) {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if coordinator.availableStandardTabs.contains(.shelf) {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if coordinator.availableStandardTabs.contains(.timer) {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        // Stats tab only shown when stats feature is enabled
        if coordinator.availableStandardTabs.contains(.stats) {
            tabsArray.append(TabModel(label: "Stats", icon: "chart.xyaxis.line", view: .stats))
        }

        // Usage tab only shown when LLM usage feature is enabled
        if coordinator.availableStandardTabs.contains(.llmUsage) {
            tabsArray.append(TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage))
        }

        if coordinator.availableStandardTabs.contains(.notes) {
            let label = Defaults[.enableNotes] ? "Notes" : "Clipboard"
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            tabsArray.append(TabModel(label: label, icon: icon, view: .notes))
        }
        if coordinator.availableStandardTabs.contains(.terminal) {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }
        return tabsArray
    }
    @ViewBuilder
    var body: some View {
        if tabBarPosition == .left {
            tabStack(vertical: true)
        } else {
            // Clipping a column to a capsule would cut the first and last icon,
            // so the shape stays with the row it was drawn for.
            tabStack(vertical: false)
                .clipShape(Capsule())
        }
    }

    private func tabStack(vertical: Bool) -> some View {
        // A layout rather than two stacks, so switching position moves the
        // icons instead of tearing the view down and building it again.
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 24))

        let stack = layout {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    select(tab)
                }
                .frame(width: vertical ? 30 : nil, height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
                .onHover { inside in
                    guard tabSwitchOnHover else { return }
                    if inside {
                        hoveredTabID = tab.id
                    } else if hoveredTabID == tab.id {
                        hoveredTabID = nil
                    }
                }
            }
        }

        return Group {
            if vertical {
                // Enough tabs to outrun the open notch's height would otherwise
                // be clipped; scrolling keeps the last of them reachable, and
                // stays inert while they all fit.
                ScrollView(.vertical, showsIndicators: false) { stack }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 30)
            } else {
                stack
            }
        }
        .onAppear {
            ensureValidSelection(with: tabs)
        }
        .onChange(of: requestedSwipeStep) { _, step in
            guard let step else { return }
            requestedSwipeStep = nil
            selectAdjacentTab(step: step)
        }
        // Arms hover switching once, a beat after the bar appears.
        .task {
            hoverArmed = false
            try? await Task.sleep(for: hoverArmingDelay)
            guard !Task.isCancelled else { return }
            hoverArmed = true
        }
        // Moving on to another icon cancels the pending switch along with the
        // task, so only the icon actually rested on ever wins.
        .task(id: hoveredTabID) {
            guard tabSwitchOnHover,
                  hoverArmed,
                  let hoveredTabID,
                  let tab = tabs.first(where: { $0.id == hoveredTabID }),
                  !isSelected(tab)
            else { return }

            try? await Task.sleep(for: hoverDwell)
            guard !Task.isCancelled else { return }
            select(tab)
        }
        // Only over the tab bar, so swipes over the content still skip tracks
        // or scroll the shelf and calendar.
        .background {
            if tabSwipeEnabled {
                Color.clear
                    .scrollPanGesture(direction: .left) { translation, phase in
                        handleTabSwipe(step: -1, translation: translation, phase: phase)
                    }
                    .scrollPanGesture(direction: .right) { translation, phase in
                        handleTabSwipe(step: 1, translation: translation, phase: phase)
                    }
            }
        }
        .onHover { inside in
            vm.isHoveringSwipeableTabBar = inside && tabSwipeEnabled
        }
        .onChange(of: tabSwipeEnabled) { _, enabled in
            if !enabled { vm.isHoveringSwipeableTabBar = false }
        }
        .onDisappear {
            vm.isHoveringSwipeableTabBar = false
        }
    }

    private var tabSwipeEnabled: Bool {
        enableGestures && swipeBetweenTabs
    }

    /// Fingers moving right go to the tab on the right, left to the one on the left.
    private func handleTabSwipe(step: Int, translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended {
            swipeHandled = false
            return
        }
        guard !swipeHandled, translation > gestureSensitivity else { return }
        swipeHandled = true
        requestedSwipeStep = step
    }

    private func selectAdjacentTab(step: Int) {
        let tabs = tabs
        guard let index = tabs.firstIndex(where: { isSelected($0) }) else { return }
        let target = index + step
        guard tabs.indices.contains(target) else { return }
        select(tabs[target])
    }

    private func select(_ tab: TabModel) {
        if tab.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = tab.experienceID
        }
        coordinator.currentView = tab.view
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
