//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

/// Groups for organizing settings tabs in the sidebar.
private enum SettingsTabGroup: String, CaseIterable, Identifiable {
    case core
    case mediaAndDisplay
    case system
    case productivity
    case utilities
    case developer
    case integrations
    case info

    var id: String { rawValue }

    /// Display title for the section header.  `nil` means no visible header.
    var title: String? {
        switch self {
        case .core:             return nil
        case .mediaAndDisplay:  return String(localized: "Media & Display")
        case .system:           return String(localized: "System")
        case .productivity:     return String(localized: "Productivity")
        case .utilities:        return String(localized: "Utilities")
        case .developer:        return String(localized: "Developer")
        case .integrations:     return String(localized: "Integrations")
        case .info:             return nil
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case lockScreen
    case media
    case devices
    case extensions
    case timer
    case calendar
    case hudAndOSD
    case battery
    case stats
    case clipboard
    case screenAssistant
    case colorPicker
    case downloads
    case shelf
    case shortcuts
    case notes
    case terminal
    case about

    var id: String { rawValue }

    /// Which sidebar group this tab belongs to.
    var group: SettingsTabGroup {
        switch self {
        case .general, .appearance:                                          return .core
        case .media, .liveActivities, .lockScreen, .devices:                 return .mediaAndDisplay
        case .hudAndOSD, .battery:                                           return .system
        case .timer, .calendar, .notes:                                      return .productivity
        case .clipboard, .screenAssistant, .colorPicker, .shelf,
             .downloads, .shortcuts:                                         return .utilities
        case .stats, .terminal:                                              return .developer
        case .extensions:                                                    return .integrations
        case .about:                                                         return .info
        }
    }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock Screen")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .extensions: return String(localized: "Extensions")
        case .timer: return String(localized: "Timer")
        case .calendar: return String(localized: "Calendar")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .stats: return String(localized: "Stats")
        case .clipboard: return String(localized: "Clipboard")
        case .screenAssistant: return String(localized: "Screen Assistant")
        case .colorPicker: return String(localized: "Color Picker")
        case .downloads: return String(localized: "Downloads")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .notes: return String(localized: "Notes")
        case .terminal: return String(localized: "Terminal")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .extensions: return "puzzlepiece.extension"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .stats: return "chart.xyaxis.line"
        case .clipboard: return "clipboard"
        case .screenAssistant: return "brain.head.profile"
        case .colorPicker: return "eyedropper"
        case .downloads: return "square.and.arrow.down"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .notes: return "note.text"
        case .terminal: return "apple.terminal"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .liveActivities: return .pink
        case .appearance: return .purple
        case .lockScreen: return .orange
        case .media: return .green
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .extensions: return Color(red: 0.557, green: 0.353, blue: 0.957)
        case .timer: return .red
        case .calendar: return .cyan
        case .hudAndOSD: return .indigo
        case .battery: return Color(red: 0.202, green: 0.783, blue: 0.348, opacity: 1.000)
        case .stats: return .teal
        case .clipboard: return .mint
        case .screenAssistant: return .pink
        case .colorPicker: return .accentColor
        case .downloads: return .gray
        case .shelf: return .brown
        case .shortcuts: return .orange
        case .notes: return Color(red: 0.979, green: 0.716, blue: 0.153, opacity: 1.000)
        case .terminal: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .about: return .secondary
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    var id: String { "\(tab.rawValue)-\(title)" }
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    fileprivate func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText: String = ""
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil) {
        self.updaterController = updaterController
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                SettingsSidebarSearchBar(
                    text: $searchText,
                    suggestions: searchSuggestions,
                    onSuggestionSelected: handleSearchSuggestionSelection
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Divider()
                    .padding(.horizontal, 12)

                List(selection: selectionBinding) {
                    ForEach(groupedFilteredTabs, id: \.group) { section in
                        Section {
                            ForEach(section.tabs) { tab in
                                NavigationLink(value: tab) {
                                    sidebarRow(for: tab)
                                }
                            }
                        } header: {
                            if let title = section.group.title {
                                Text(title)
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
                .environment(\.defaultMinListRowHeight, 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } detail: {
            detailView(for: resolvedSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar { toolbarSpacingShim }
        .environmentObject(highlightCoordinator)
        .formStyle(.grouped)
        .frame(width: 700)
        .onChange(of: searchText) { _, newValue in
            let matches = tabsMatchingSearch(newValue)
            guard let firstMatch = matches.first else { return }
            if !matches.contains(resolvedSelection) {
                selectedTab = firstMatch
            }
        }
        .background {
            Group {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .glassEffect(
                            .clear
                                .tint(Color.white.opacity(0.1))
                                .interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                } else {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private var resolvedSelection: SettingsTab {
        availableTabs.contains(selectedTab) ? selectedTab : (availableTabs.first ?? .general)
    }

    @ToolbarContentBuilder
    private var toolbarSpacingShim: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
        }
    }

    @ViewBuilder
    private var toolbarSpacerView: some View {
        Color.clear
            .frame(width: 96, height: 32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var filteredTabs: [SettingsTab] {
        tabsMatchingSearch(searchText)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }

    @ViewBuilder
    private func sidebarIcon(for tab: SettingsTab) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tab.tint.opacity(1),
                        tab.tint.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 26, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7)
                    .blendMode(.plusLighter)
            }
            .shadow(color: tab.tint.opacity(0.35), radius: 2, x: 0, y: 1)
            .overlay {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(for: tab)
            Text(tab.title)
            if tab == .downloads {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            } else if tab == .extensions {
                Spacer()
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var availableTabs: [SettingsTab] {
        // Ordered to match group layout: core → media & display → system →
        // productivity → utilities → developer → integrations → info.
        let ordered: [SettingsTab] = [
            // Core
            .general,
            .appearance,
            // Media & Display
            .media,
            .liveActivities,
            .lockScreen,
            .devices,
            // System
            .hudAndOSD,
            .battery,
            // Productivity
            .timer,
            .calendar,
            .notes,
            // Utilities
            .clipboard,
            .screenAssistant,
            .colorPicker,
            .shelf,
            .downloads,
            .shortcuts,
            // Developer
            .stats,
            .terminal,
            // Integrations
            .extensions,
            // Info
            .about
        ]

        return ordered.filter { isTabVisible($0) }
    }

    /// Groups the filtered tabs into sidebar sections, preserving both
    /// the group order and the per-group tab order from `availableTabs`.
    private var groupedFilteredTabs: [(group: SettingsTabGroup, tabs: [SettingsTab])] {
        let visible = filteredTabs
        var result: [(group: SettingsTabGroup, tabs: [SettingsTab])] = []

        for group in SettingsTabGroup.allCases {
            let tabs = visible.filter { $0.group == group }
            if !tabs.isEmpty {
                result.append((group: group, tabs: tabs))
            }
        }

        return result
    }

    private func tabsMatchingSearch(_ query: String) -> [SettingsTab] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return availableTabs }

        let entryMatches = searchEntries(matching: trimmed)
        let matchingTabs = Set(entryMatches.map(\.tab))

        return availableTabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(trimmed) || matchingTabs.contains(tab)
        }
    }

    private var searchSuggestions: [SettingsSearchEntry] {
        Array(searchEntries(matching: searchText).filter { $0.tab != .downloads }.prefix(8))
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        guard suggestion.tab != .downloads else { return }
        highlightCoordinator.focus(on: suggestion)
        selectedTab = suggestion.tab
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSuggestions)
        }

        private var showSuggestions: Bool {
            isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Settings", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
        }

        private var suggestionList: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(suggestion.tab.tint)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(suggestion.tab.title)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? Color.white.opacity(0.08) : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    private func searchEntries(matching query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return settingsSearchIndex
            .filter { availableTabs.contains($0.tab) }
            .filter { entry in
                entry.title.localizedCaseInsensitiveContains(trimmed) ||
                entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
    }

    private var settingsSearchIndex: [SettingsSearchEntry] {
        [
            // General
            SettingsSearchEntry(tab: .general, title: "Enable Minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.general.highlightID(for: "Enable Minimalistic UI")),
            SettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
            SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
            SettingsSearchEntry(tab: .general, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.general.highlightID(for: "Show on all displays")),
            SettingsSearchEntry(tab: .general, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.general.highlightID(for: "Show on a specific display")),
            SettingsSearchEntry(tab: .general, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.general.highlightID(for: "Automatically switch displays")),
            SettingsSearchEntry(tab: .general, title: "Hide Dynamic Island during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.general.highlightID(for: "Hide Dynamic Island during screenshots & recordings")),
            SettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
            SettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
            SettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
            SettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
            SettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
            SettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
            SettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
            SettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
            SettingsSearchEntry(tab: .general, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Hide until hovered")),
            SettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),

            // Live Activities
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Screen Recording Detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Screen Recording Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Recording Indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Recording Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Focus Detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Indicator")),
            SettingsSearchEntry(tab: .liveActivities, title: "Show Focus Label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Label")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Camera Detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Camera Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable Microphone Detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Microphone Detection")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),
            SettingsSearchEntry(tab: .liveActivities, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable reminder live activity")),

            // Battery (Charge)
            SettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
            SettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
            SettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
            SettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),

            // HUDs
            SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
            SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
            SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
            SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
            SettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

            // Custom OSD
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
            SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

            // Media
            SettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
            SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
            SettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
            SettingsSearchEntry(tab: .media, title: "Enable lyrics", keywords: ["lyrics", "song text"], highlightID: SettingsTab.media.highlightID(for: "Enable lyrics")),
            SettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
            SettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax", keywords: ["parallax", "lock screen", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax")),
            SettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),

            // Calendar
            SettingsSearchEntry(tab: .calendar, title: "Show calendar", keywords: ["calendar", "events"], highlightID: SettingsTab.calendar.highlightID(for: "Show calendar")),
            SettingsSearchEntry(tab: .calendar, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.calendar.highlightID(for: "Enable reminder live activity")),
            SettingsSearchEntry(tab: .calendar, title: "Countdown style", keywords: ["reminder countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Countdown style")),
            SettingsSearchEntry(tab: .calendar, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.calendar.highlightID(for: "Show lock screen reminder")),
            SettingsSearchEntry(tab: .calendar, title: "Show next calendar event", keywords: ["calendar widget", "lock screen", "next event"], highlightID: SettingsTab.calendar.highlightID(for: "Show next calendar event")),
            SettingsSearchEntry(tab: .calendar, title: "Show events within the next", keywords: ["calendar widget", "lookahead"], highlightID: SettingsTab.calendar.highlightID(for: "Show events within the next")),
            SettingsSearchEntry(tab: .calendar, title: "Show events from all calendars", keywords: ["calendar widget", "selection"], highlightID: SettingsTab.calendar.highlightID(for: "Show events from all calendars")),
            SettingsSearchEntry(tab: .calendar, title: "Show countdown", keywords: ["calendar widget", "countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Show countdown")),
            SettingsSearchEntry(tab: .calendar, title: "Show event for entire duration", keywords: ["calendar widget", "duration"], highlightID: SettingsTab.calendar.highlightID(for: "Show event for entire duration")),
            SettingsSearchEntry(tab: .calendar, title: "Hide active event and show next upcoming event", keywords: ["calendar widget", "after start"], highlightID: SettingsTab.calendar.highlightID(for: "Hide active event and show next upcoming event")),
            SettingsSearchEntry(tab: .calendar, title: "Show time remaining", keywords: ["calendar widget", "remaining"], highlightID: SettingsTab.calendar.highlightID(for: "Show time remaining")),
            SettingsSearchEntry(tab: .calendar, title: "Show start time after event begins", keywords: ["calendar widget", "start time"], highlightID: SettingsTab.calendar.highlightID(for: "Show start time after event begins")),
            SettingsSearchEntry(tab: .calendar, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.calendar.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .calendar, title: "Hide all-day events", keywords: ["calendar", "all-day"], highlightID: SettingsTab.calendar.highlightID(for: "Hide all-day events")),
            SettingsSearchEntry(tab: .calendar, title: "Hide completed reminders", keywords: ["reminder", "completed"], highlightID: SettingsTab.calendar.highlightID(for: "Hide completed reminders")),
            SettingsSearchEntry(tab: .calendar, title: "Show full event titles", keywords: ["calendar", "titles"], highlightID: SettingsTab.calendar.highlightID(for: "Show full event titles")),
            SettingsSearchEntry(tab: .calendar, title: "Auto-scroll to next event", keywords: ["calendar", "scroll"], highlightID: SettingsTab.calendar.highlightID(for: "Auto-scroll to next event")),

            // Shelf
            SettingsSearchEntry(tab: .shelf, title: "Enable shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Enable shelf")),
            SettingsSearchEntry(tab: .shelf, title: "Open shelf tab by default if items added", keywords: ["auto open", "shelf tab"], highlightID: SettingsTab.shelf.highlightID(for: "Open shelf tab by default if items added")),
            SettingsSearchEntry(tab: .shelf, title: "Expanded drag detection area", keywords: ["shelf", "drag"], highlightID: SettingsTab.shelf.highlightID(for: "Expanded drag detection area")),
            SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
            SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
            SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
            SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

            // Appearance
            SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
            SettingsSearchEntry(tab: .appearance, title: "Settings icon in notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Settings icon in notch")),
            SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
            SettingsSearchEntry(tab: .appearance, title: "Corner radius scaling", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius scaling")),
            SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
            SettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
            SettingsSearchEntry(tab: .appearance, title: "Enable colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored spectrograms")),
            SettingsSearchEntry(tab: .appearance, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.appearance.highlightID(for: "Enable blur effect behind album art")),
            SettingsSearchEntry(tab: .appearance, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.appearance.highlightID(for: "Slider color")),
            SettingsSearchEntry(tab: .appearance, title: "Enable Dynamic mirror", keywords: ["mirror", "reflection"], highlightID: SettingsTab.appearance.highlightID(for: "Enable Dynamic mirror")),
            SettingsSearchEntry(tab: .appearance, title: "Mirror shape", keywords: ["mirror shape", "circle", "rectangle"], highlightID: SettingsTab.appearance.highlightID(for: "Mirror shape")),
            SettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
            SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

            // Lock Screen
            SettingsSearchEntry(tab: .lockScreen, title: "Preview lock screen widgets", keywords: ["preview", "lock screen", "widgets"], highlightID: SettingsTab.lockScreen.highlightID(for: "Preview lock screen widgets")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
            SettingsSearchEntry(tab: .lockScreen, title: "Play lock/unlock sounds", keywords: ["chime", "sound"], highlightID: SettingsTab.lockScreen.highlightID(for: "Play lock/unlock sounds")),
            SettingsSearchEntry(tab: .lockScreen, title: "Material", keywords: ["glass", "frosted", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen media panel", keywords: ["media panel", "lock screen media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen media panel")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show media app icon", keywords: ["app icon", "media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show media app icon")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show panel border", keywords: ["panel border"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show panel border")),
            SettingsSearchEntry(tab: .lockScreen, title: "Enable media panel blur", keywords: ["blur", "media panel"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable media panel blur")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen timer", keywords: ["timer widget", "lock screen timer"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen timer")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .lockScreen, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen weather", keywords: ["weather widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen weather")),
            SettingsSearchEntry(tab: .lockScreen, title: "Layout", keywords: ["inline", "circular", "weather layout"], highlightID: SettingsTab.lockScreen.highlightID(for: "Layout")),
            SettingsSearchEntry(tab: .lockScreen, title: "Weather data provider", keywords: ["wttr", "open meteo"], highlightID: SettingsTab.lockScreen.highlightID(for: "Weather data provider")),
            SettingsSearchEntry(tab: .lockScreen, title: "Temperature unit", keywords: ["celsius", "fahrenheit"], highlightID: SettingsTab.lockScreen.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show location label", keywords: ["location", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show location label")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging status", keywords: ["charging", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging status")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show charging percentage", keywords: ["charging percentage"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging percentage")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show battery indicator", keywords: ["battery gauge", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show battery indicator")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use MacBook icon when on battery", keywords: ["laptop icon", "battery"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use MacBook icon when on battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show Bluetooth battery", keywords: ["bluetooth", "gauge"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show Bluetooth battery")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show AQI widget", keywords: ["air quality", "aqi"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show AQI widget")),
            SettingsSearchEntry(tab: .lockScreen, title: "Air quality scale", keywords: ["aqi", "scale"], highlightID: SettingsTab.lockScreen.highlightID(for: "Air quality scale")),
            SettingsSearchEntry(tab: .lockScreen, title: "Use colored gauges", keywords: ["gauge tint", "monochrome"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use colored gauges")),
            SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen reminder")),
            SettingsSearchEntry(tab: .lockScreen, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.lockScreen.highlightID(for: "Chip color")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder alignment", keywords: ["reminder", "alignment", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder alignment")),
            SettingsSearchEntry(tab: .lockScreen, title: "Reminder vertical offset", keywords: ["reminder", "offset", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder vertical offset")),

            // Extensions
            SettingsSearchEntry(tab: .extensions, title: "Enable third-party extensions", keywords: ["extensions", "authorization", "third party"], highlightID: SettingsTab.extensions.highlightID(for: "Enable third-party extensions")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension live activities", keywords: ["extensions", "live activities", "permissions"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension live activities")),
            SettingsSearchEntry(tab: .extensions, title: "Allow extension lock screen widgets", keywords: ["extensions", "lock screen", "widgets"], highlightID: SettingsTab.extensions.highlightID(for: "Allow extension lock screen widgets")),
            SettingsSearchEntry(tab: .extensions, title: "Enable extension diagnostics logging", keywords: ["extensions", "diagnostics", "logging"], highlightID: SettingsTab.extensions.highlightID(for: "Enable extension diagnostics logging")),
            SettingsSearchEntry(tab: .extensions, title: "Manage app permissions", keywords: ["extensions", "permissions", "apps"], highlightID: SettingsTab.extensions.highlightID(for: "App permissions list")),

            // Shortcuts
            SettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

            // Timer
            SettingsSearchEntry(tab: .timer, title: "Enable timer feature", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Enable timer feature")),
            SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
            SettingsSearchEntry(tab: .timer, title: "Show lock screen timer widget", keywords: ["lock screen", "timer widget"], highlightID: SettingsTab.timer.highlightID(for: "Show lock screen timer widget")),
            SettingsSearchEntry(tab: .timer, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.timer.highlightID(for: "Timer surface")),
            SettingsSearchEntry(tab: .timer, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.timer.highlightID(for: "Timer glass material")),
            SettingsSearchEntry(tab: .timer, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Timer liquid mode")),
            SettingsSearchEntry(tab: .timer, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.timer.highlightID(for: "Timer widget variant")),
            SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
            SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
            SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
            SettingsSearchEntry(tab: .timer, title: "Accent colour", keywords: ["accent", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Accent colour")),

            // Stats
            SettingsSearchEntry(tab: .stats, title: "Enable system stats monitoring", keywords: ["stats", "monitoring"], highlightID: SettingsTab.stats.highlightID(for: "Enable system stats monitoring")),
            SettingsSearchEntry(tab: .stats, title: "Stop monitoring after closing the notch", keywords: ["stats", "auto stop"], highlightID: SettingsTab.stats.highlightID(for: "Stop monitoring after closing the notch")),
            SettingsSearchEntry(tab: .stats, title: "CPU Usage", keywords: ["cpu", "graph"], highlightID: SettingsTab.stats.highlightID(for: "CPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Temperature unit", keywords: ["cpu", "temperature", "celsius", "fahrenheit"], highlightID: SettingsTab.stats.highlightID(for: "Temperature unit")),
            SettingsSearchEntry(tab: .stats, title: "Memory Usage", keywords: ["memory", "ram"], highlightID: SettingsTab.stats.highlightID(for: "Memory Usage")),
            SettingsSearchEntry(tab: .stats, title: "GPU Usage", keywords: ["gpu", "graphics"], highlightID: SettingsTab.stats.highlightID(for: "GPU Usage")),
            SettingsSearchEntry(tab: .stats, title: "Network Activity", keywords: ["network", "graph"], highlightID: SettingsTab.stats.highlightID(for: "Network Activity")),
            SettingsSearchEntry(tab: .stats, title: "Disk I/O", keywords: ["disk", "io"], highlightID: SettingsTab.stats.highlightID(for: "Disk I/O")),

            // Clipboard
            SettingsSearchEntry(tab: .clipboard, title: "Enable Clipboard Manager", keywords: ["clipboard", "manager"], highlightID: SettingsTab.clipboard.highlightID(for: "Enable Clipboard Manager")),
            SettingsSearchEntry(tab: .clipboard, title: "Show Clipboard Icon", keywords: ["icon", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Show Clipboard Icon")),
            SettingsSearchEntry(tab: .clipboard, title: "Display Mode", keywords: ["list", "grid", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "Display Mode")),
            SettingsSearchEntry(tab: .clipboard, title: "History Size", keywords: ["history", "clipboard"], highlightID: SettingsTab.clipboard.highlightID(for: "History Size")),

            // Screen Assistant
            SettingsSearchEntry(tab: .screenAssistant, title: "Enable Screen Assistant", keywords: ["screen assistant", "ai"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Enable Screen Assistant")),
            SettingsSearchEntry(tab: .screenAssistant, title: "Display Mode", keywords: ["screen assistant", "mode"], highlightID: SettingsTab.screenAssistant.highlightID(for: "Display Mode")),

            // Color Picker
            SettingsSearchEntry(tab: .colorPicker, title: "Enable Color Picker", keywords: ["color picker", "eyedropper"], highlightID: SettingsTab.colorPicker.highlightID(for: "Enable Color Picker")),
            SettingsSearchEntry(tab: .colorPicker, title: "Show Color Picker Icon", keywords: ["color icon", "toolbar"], highlightID: SettingsTab.colorPicker.highlightID(for: "Show Color Picker Icon")),
            SettingsSearchEntry(tab: .colorPicker, title: "Display Mode", keywords: ["color", "list"], highlightID: SettingsTab.colorPicker.highlightID(for: "Display Mode")),
            SettingsSearchEntry(tab: .colorPicker, title: "History Size", keywords: ["color history"], highlightID: SettingsTab.colorPicker.highlightID(for: "History Size")),
            SettingsSearchEntry(tab: .colorPicker, title: "Show All Color Formats", keywords: ["hex", "hsl", "color formats"], highlightID: SettingsTab.colorPicker.highlightID(for: "Show All Color Formats")),

            // Terminal
            SettingsSearchEntry(tab: .terminal, title: "Enable terminal", keywords: ["terminal", "guake", "shell"], highlightID: SettingsTab.terminal.highlightID(for: "Enable terminal")),
            SettingsSearchEntry(tab: .terminal, title: "Shell path", keywords: ["shell", "zsh", "bash", "terminal"], highlightID: SettingsTab.terminal.highlightID(for: "Shell path")),
            SettingsSearchEntry(tab: .terminal, title: "Font size", keywords: ["terminal", "font", "text size"], highlightID: SettingsTab.terminal.highlightID(for: "Font size")),
            SettingsSearchEntry(tab: .terminal, title: "Terminal opacity", keywords: ["terminal", "opacity", "transparency", "blur", "background"], highlightID: SettingsTab.terminal.highlightID(for: "Terminal opacity")),
            SettingsSearchEntry(tab: .terminal, title: "Maximum height", keywords: ["terminal", "height", "size"], highlightID: SettingsTab.terminal.highlightID(for: "Maximum height")),
            SettingsSearchEntry(tab: .terminal, title: "Background color", keywords: ["terminal", "background", "color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Background color")),
            SettingsSearchEntry(tab: .terminal, title: "Foreground color", keywords: ["terminal", "foreground", "text color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Foreground color")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor color", keywords: ["terminal", "cursor", "caret", "color"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor color")),
            SettingsSearchEntry(tab: .terminal, title: "Bold as bright", keywords: ["terminal", "bold", "bright", "colors"], highlightID: SettingsTab.terminal.highlightID(for: "Bold as bright")),
            SettingsSearchEntry(tab: .terminal, title: "Cursor style", keywords: ["terminal", "cursor", "block", "underline", "bar", "blink"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor style")),
            SettingsSearchEntry(tab: .terminal, title: "Scrollback lines", keywords: ["terminal", "scrollback", "buffer", "history"], highlightID: SettingsTab.terminal.highlightID(for: "Scrollback lines")),
            SettingsSearchEntry(tab: .terminal, title: "Option as Meta", keywords: ["terminal", "option", "meta", "alt", "key"], highlightID: SettingsTab.terminal.highlightID(for: "Option as Meta")),
            SettingsSearchEntry(tab: .terminal, title: "Mouse reporting", keywords: ["terminal", "mouse", "reporting", "vim", "tmux"], highlightID: SettingsTab.terminal.highlightID(for: "Mouse reporting")),
        ]
    }

    private func isTabVisible(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .timer, .stats, .clipboard, .screenAssistant, .colorPicker, .shelf, .notes, .terminal:
            return !enableMinimalisticUI
        default:
            return true
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsForm(tab: .general) {
                GeneralSettings()
            }
        case .liveActivities:
            SettingsForm(tab: .liveActivities) {
                LiveActivitiesSettings()
            }
        case .appearance:
            SettingsForm(tab: .appearance) {
                Appearance()
            }
        case .lockScreen:
            SettingsForm(tab: .lockScreen) {
                LockScreenSettings()
            }
        case .media:
            SettingsForm(tab: .media) {
                Media()
            }
        case .devices:
            SettingsForm(tab: .devices) {
                DevicesSettingsView()
            }
        case .extensions:
            SettingsForm(tab: .extensions) {
                ExtensionsSettingsView()
            }
        case .timer:
            SettingsForm(tab: .timer) {
                TimerSettings()
            }
        case .calendar:
            SettingsForm(tab: .calendar) {
                CalendarSettings()
            }
        case .hudAndOSD:
            SettingsForm(tab: .hudAndOSD) {
                HUDAndOSDSettingsView()
            }
        case .battery:
            SettingsForm(tab: .battery) {
                Charge()
            }
        case .stats:
            SettingsForm(tab: .stats) {
                StatsSettings()
            }
        case .clipboard:
            SettingsForm(tab: .clipboard) {
                ClipboardSettings()
            }
        case .screenAssistant:
            SettingsForm(tab: .screenAssistant) {
                ScreenAssistantSettings()
            }
        case .colorPicker:
            SettingsForm(tab: .colorPicker) {
                ColorPickerSettings()
            }
        case .downloads:
            SettingsForm(tab: .downloads) {
                Downloads()
            }
        case .shelf:
            SettingsForm(tab: .shelf) {
                Shelf()
            }
        case .shortcuts:
            SettingsForm(tab: .shortcuts) {
                Shortcuts()
            }
        case .notes:
            SettingsForm(tab: .notes) {
                NotesSettingsView()
            }
        case .terminal:
            SettingsForm(tab: .terminal) {
                TerminalSettings()
            }
        case .about:
            if let controller = updaterController {
                SettingsForm(tab: .about) {
                    About(updaterController: controller)
                }
            } else {
                SettingsForm(tab: .about) {
                    About(updaterController: SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil))
                }
            }
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) var musicGestureBehavior
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover

    private func highlightID(_ title: String) -> String {
        SettingsTab.general.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableMinimalisticUI) {
                    Text("Enable Minimalistic UI")
                }
                .onChange(of: enableMinimalisticUI) { _, newValue in
                    if newValue {
                        // Auto-enable simpler animation mode
                        Defaults[.useModernCloseAnimation] = true
                    }
                }
                .settingsHighlight(id: highlightID("Enable Minimalistic UI"))
            } header: {
                Text("UI Mode")
            } footer: {
                Text("Minimalistic mode focuses on media controls and system HUDs, hiding all extra features for a clean, focused experience. Automatically enables simpler animations.")
            }

            Section {
                Defaults.Toggle(key: .menubarIcon) {
                    Text("Menubar icon")
                }
                .settingsHighlight(id: highlightID("Menubar icon"))
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                .settingsHighlight(id: highlightID("Launch at login"))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Show on all displays"))
                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Show on a specific display"))
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Automatically switch displays"))
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("Hide Dynamic Island during screenshots & recordings")
                }
                .settingsHighlight(id: highlightID("Hide Dynamic Island during screenshots & recordings"))
            } header: {
                Text("System features")
            }

            Section {
                Picker(selection: $notchHeightMode, label:
                        Text("Notch display height")) {
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                        .onChange(of: notchHeightMode) {
                            switch notchHeightMode {
                            case .matchRealNotchSize:
                                notchHeight = 38
                            case .matchMenuBar:
                                notchHeight = 44
                            case .custom:
                                notchHeight = 38
                            }
                            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        }
                        .settingsHighlight(id: highlightID("Notch display height"))
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch Height")
            }

            NotchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            .settingsHighlight(id: highlightID("Enable gestures"))
            if enableGestures {
                Defaults.Toggle(key: .enableHorizontalMusicGestures) {
                    Text("Media change with horizontal gestures")
                }
                .settingsHighlight(id: highlightID("Horizontal media gestures"))

                if enableHorizontalMusicGestures {
                    Picker("Gesture skip behavior", selection: $musicGestureBehavior) {
                        ForEach(MusicSkipBehavior.allCases) { behavior in
                            Text(behavior.displayName)
                                .tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Gesture skip behavior"))

                    Text(musicGestureBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Defaults.Toggle(key: .reverseSwipeGestures) {
                        Text("Reverse swipe gestures")
                    }
                    .settingsHighlight(id: highlightID("Reverse swipe gestures"))
                }

                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .settingsHighlight(id: highlightID("Close gesture"))
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .reverseScrollGestures) {
                    Text("Reverse open/close scroll gestures")
                }
                .settingsHighlight(id: highlightID("Reverse scroll gestures"))
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .extendHoverArea) {
                Text("Extend hover area")
            }
            .settingsHighlight(id: highlightID("Extend hover area"))
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable haptics")
            }
            .settingsHighlight(id: highlightID("Enable haptics"))
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            .settingsHighlight(id: highlightID("Open notch on hover"))
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("External display style", selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.localizedName)
                        .tag(style)
                }
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("External display style"))
            Text(externalDisplayStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                Text("Hide until hovered on non-notch displays")
            }
            .settingsHighlight(id: highlightID("Hide until hovered"))
            Text("When enabled, the notch slides up and hides on external (non-notch) displays until you hover over it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    private func highlightID(_ title: String) -> String {
        SettingsTab.battery.highlightID(for: title)
    }

    var body: some View {
        Form {
            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .showBatteryIndicator) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))
                    Defaults.Toggle(key: .showPowerStatusNotifications) {
                        Text("Show power status notifications")
                    }
                    .settingsHighlight(id: highlightID("Show power status notifications"))
                    Defaults.Toggle(key: .playLowBatteryAlertSound) {
                        Text("Play low battery alert sound")
                    }
                    .settingsHighlight(id: highlightID("Play low battery alert sound"))
                } header: {
                    Text("General")
                }
                Section {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                    .settingsHighlight(id: highlightID("Show battery percentage"))
                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Show power status icons")
                    }
                    .settingsHighlight(id: highlightID("Show power status icons"))
                } header: {
                    Text("Battery Information")
                }
            } else {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        Image("battery.100percent.slash")
                            .font(.title)
                        Text("Battery settings and informations are only available on MacBooks")
                            .font(.title3)
                    }
                }
            }
        }
        .navigationTitle("Battery")
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.downloads.highlightID(for: title)
    }

    var body: some View {
        SwiftUI.Form {
            Section {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Enable download detection")
                }
                .settingsHighlight(id: highlightID("Enable download detection"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download indicator style")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 16) {
                        DownloadStyleButton(
                            style: .progress,
                            isSelected: selectedDownloadIndicatorStyle == .progress,
                            disabled: !Defaults[.enableDownloadListener]
                        ) {
                            selectedDownloadIndicatorStyle = .progress
                        }

                        DownloadStyleButton(
                            style: .circle,
                            isSelected: selectedDownloadIndicatorStyle == .circle,
                            disabled: !Defaults[.enableDownloadListener]
                        ) {
                            selectedDownloadIndicatorStyle = .circle
                        }
                    }
                }
                .settingsHighlight(id: highlightID("Download indicator style"))
            } header: {
                Text("Download Detection")
            } footer: {
                Text("Monitor your Downloads folder for Chromium-style downloads (.crdownload files) and show a live activity in the Dynamic Island while downloads are in progress.")
            }
        }
        .navigationTitle("Downloads")
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    if style == .progress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    } else {
                        SpinningCircleDownloadView()
                    }
                }
                .frame(width: 80, height: 60)
                .onHover { hovering in
                    if !disabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                }

                Text(style.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled {
                    action()
                }
            }
            .opacity(disabled ? 0.5 : 1.0)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

private struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var paneBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                HUDSelectionCard(
                    title: String(localized: "Dynamic Island"),
                    isSelected: selectedTab == .hud,
                    action: {
                        selectedTab = .hud
                        enableSystemHUD = true
                        enableCustomOSD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 64, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            .overlay {
                                HStack(spacing: 6) {
                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 12)

                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.white.opacity(0.2))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white)
                                                    .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                    .animation(.spring(response: 0.3), value: previewModel.level)
                                            }
                                    }
                                    .frame(height: 4)
                                }
                                .padding(.horizontal, 8)
                            }
                    }
                }

                HUDSelectionCard(
                    title: String(localized: "Custom OSD"),
                    isSelected: selectedTab == .osd,
                    action: {
                        selectedTab = .osd
                        enableCustomOSD = true
                        enableSystemHUD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))

                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary)
                                                .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                }
                                .frame(width: 36, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                }

                HUDSelectionCard(
                    title: String(localized: "Vertical Bar"),
                    isSelected: selectedTab == .vertical,
                    action: {
                        selectedTab = .vertical
                        enableVerticalHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white)
                                            .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                            .animation(.spring(response: 0.3), value: previewModel.level)
                                    }
                                }
                                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.bottom, 2)

                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(4)
                        }
                        .frame(width: 22, height: 54)
                }

                HUDSelectionCard(
                    title: String(localized: "Circular"),
                    isSelected: selectedTab == .circular,
                    action: {
                        selectedTab = .circular
                        enableCircularHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableVerticalHUD = false
                    }
                ) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(previewModel.level))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3), value: previewModel.level)
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .padding(.top, 8)

            switch selectedTab {
            case .hud:
                HUD()
            case .osd:
                if #available(macOS 15.0, *) {
                    CustomOSDSettings()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("macOS 15 or later required")
                            .font(.headline)

                        Text("Custom OSD feature requires macOS 15 or later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            case .vertical:
                Form {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Vertical HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabled(enableThirdPartyDDCIntegration)
                                .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active — brightness keys are handled by the external app." : "")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $verticalHUDShowValue)
                        Toggle("Use Accent Color", isOn: $verticalHUDUseAccentColor)
                        Toggle("Interactive (Drag to Change)", isOn: $verticalHUDInteractive)
                        Picker("Material", selection: $verticalHUDMaterial) {
                            ForEach(availableVerticalMaterials, id: \.self) { material in
                                Text(material.rawValue).tag(material)
                            }
                        }

                        if verticalHUDMaterial == .liquid {
                            if #available(macOS 26.0, *) {
                                Picker("Glass mode", selection: $verticalHUDLiquidGlassCustomizationMode) {
                                    ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Custom liquid variant")
                                            Spacer()
                                            Text("v\(verticalHUDLiquidGlassVariant.rawValue)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: verticalLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                    }
                                }
                            } else {
                                Text("Custom Liquid is available on macOS 26 or later.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Behavior & Style")
                    }

                    Section {
                        Picker("HUD Position", selection: $verticalHUDPosition) {
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.menu)

                        VStack(alignment: .leading) {
                            Text("Screen Padding: \(Int(verticalHUDPadding))px")
                            Slider(value: $verticalHUDPadding, in: 0...100, step: 4)
                        }
                    } header: {
                        Text("Position")
                    } footer: {
                        Text("Choose directly on which side of the screen the vertical bar appears.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Width: \(Int(verticalHUDWidth))px")
                            Slider(value: $verticalHUDWidth, in: 24...80, step: 2)
                        }
                        VStack(alignment: .leading) {
                            Text("Height: \(Int(verticalHUDHeight))px")
                            Slider(value: $verticalHUDHeight, in: 100...500, step: 10)
                        }
                        Button("Reset to Default") {
                            verticalHUDWidth = 36
                            verticalHUDHeight = 160
                            verticalHUDPadding = 24
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }

            case .circular:
                Form {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Circular HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabled(enableThirdPartyDDCIntegration)
                                .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active — brightness keys are handled by the external app." : "")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $circularHUDShowValue)
                        Toggle("Use Accent Color", isOn: $circularHUDUseAccentColor)
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Style")
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Size: \(Int(circularHUDSize))px")
                            Slider(value: $circularHUDSize, in: 40...200, step: 5)
                        }
                        VStack(alignment: .leading) {
                            Text("Line Width: \(Int(circularHUDStrokeWidth))px")
                            Slider(value: $circularHUDStrokeWidth, in: 2...16, step: 1)
                        }
                        Button("Reset to Default") {
                            circularHUDSize = 65
                            circularHUDStrokeWidth = 4
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }
            }

            // Third-party display integrations (shared across all HUD variants)
            ExternalDisplayIntegrationsSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(paneBackgroundColor)
        .navigationTitle("Controls")
        .onAppear {
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
        }
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return "Running" }
            if betterDisplayManager.isDetected { return "Not running" }
            return "Not detected"
        case .lunar:
            if lunarManager.isConnected { return "Connected" }
            if lunarManager.isRunning { return "Running" }
            if lunarManager.isDetected { return "Not running" }
            return "Not detected"
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if betterDisplayManager.isRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if lunarManager.isRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through Atoll's HUD."
            }
            if !betterDisplayManager.isRunning {
                return "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration."
            }
            return "BetterDisplay OSD events will be routed through Atoll's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through Atoll's HUD via DDC."
            }
            if !lunarManager.isRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through Atoll's HUD; volume follows when external volume control listener is enabled below."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable third-party DDC app integration", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    Picker("Provider", selection: $thirdPartyDDCProvider) {
                        ForEach(ThirdPartyDDCProvider.allCases) { provider in
                            HStack {
                                AppIconImage(
                                    bundleIdentifiers: provider.bundleIdentifiers,
                                    symbolFallback: "display",
                                    symbolColor: .secondary
                                )
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("Enable external volume control listener", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("Enable external volume control listener"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "Atoll's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "Atoll keeps native volume key interception. External provider volume payloads are ignored while this is off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("Enable to route BetterDisplay or Lunar display adjustments through Atoll's active HUD style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("Atoll always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                .frame(width: 110, height: 80)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct DevicesSettingsView: View {
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.useBluetoothHUD3DIcon) private var useBluetoothHUD3DIcon

    private func highlightID(_ title: String) -> String {
        SettingsTab.devices.highlightID(for: title)
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) {
                    Text("Show Bluetooth device connections")
                }
                .settingsHighlight(id: highlightID("Show Bluetooth device connections"))
                Defaults.Toggle(key: .useCircularBluetoothBatteryIndicator) {
                    Text("Use circular battery indicator")
                }
                .settingsHighlight(id: highlightID("Use circular battery indicator"))
                Defaults.Toggle(key: .showBluetoothBatteryPercentageText) {
                    Text("Show battery percentage text in HUD")
                }
                .settingsHighlight(id: highlightID("Show battery percentage text in HUD"))
                Defaults.Toggle(key: .showBluetoothDeviceNameMarquee) {
                    Text("Scroll device name in HUD")
                }
                .settingsHighlight(id: highlightID("Scroll device name in HUD"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("HUD icon style")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        BluetoothHUDIconStyleCard(
                            style: .symbol,
                            isSelected: !useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = false
                        }
                        BluetoothHUDIconStyleCard(
                            style: .threeD,
                            isSelected: useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = true
                        }
                        Spacer(minLength: 0)
                    }
                }
                .settingsHighlight(id: highlightID("Use 3D Bluetooth HUD icon"))
            } header: {
                Text("Bluetooth Audio Devices")
            } footer: {
                Text("Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedBatteryDisplay) {
                    Text("Color-coded battery display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded battery display"))
            } header: {
                Text("Battery Indicator Styling")
            } footer: {
                if progressBarStyle == .segmented {
                    Text("Color-coded fills are unavailable in Segmented mode. Switch to Hierarchical or Gradient inside Controls › Dynamic Island to adjust advanced options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill. Adjust gradient behavior from Controls › Dynamic Island.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Devices")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission lets Dynamic Island replace the native volume, brightness, and keyboard HUDs.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }



            if enableSystemHUD && !Defaults[.enableCustomOSD] && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
                Section {
                    Toggle("Volume HUD", isOn: $enableVolumeHUD)
                    Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                    Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                        .disabled(enableThirdPartyDDCIntegration)
                        .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active \u{2014} brightness keys are handled by the external app." : "")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display HUD notifications.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Defaults.Toggle(key: .playVolumeChangeFeedback) {
                    Text("Play feedback when volume is changed")
                }
                .settingsHighlight(id: highlightID("Play feedback when volume is changed"))
                .help("Plays the supplied feedback clip whenever you press the hardware volume keys.")
            } header: {
                Text("Audio feedback")
            } footer: {
                Text("Requires Accessibility permission so Dynamic Island can intercept the hardware volume keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                    Text("Color-coded volume display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded volume display"))

                if !colorCodingDisabled && (Defaults[.useColorCodedBatteryDisplay] || Defaults[.useColorCodedVolumeDisplay]) {
                    Defaults.Toggle(key: .useSmoothColorGradient) {
                        Text("Smooth color transitions")
                    }
                    .settingsHighlight(id: highlightID("Smooth color transitions"))
                }

                Defaults.Toggle(key: .showProgressPercentages) {
                    Text("Show percentages beside progress bars")
                }
                .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
            } header: {
                Text("Dynamic Island Progress Bars")
            } footer: {
                if colorCodingDisabled {
                    Text("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .settingsHighlight(id: highlightID("HUD style"))
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                Picker("Progressbar style", selection: $progressBarStyle) {
                    Text("Hierarchical")
                        .tag(ProgressBarStyle.hierarchical)
                    Text("Gradient")
                        .tag(ProgressBarStyle.gradient)
                    Text("Segmented")
                        .tag(ProgressBarStyle.segmented)
                }
                .settingsHighlight(id: highlightID("Progressbar style"))
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                .settingsHighlight(id: highlightID("Enable glowing effect"))
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Use accent color")
                }
                .settingsHighlight(id: highlightID("Use accent color"))
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .navigationTitle("Controls")
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenMusicAlbumParallaxEnabled
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity

    
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.media.highlightID(for: title)
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music Source"))
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .font(.caption)
                            .foregroundColor(.blue) // Ensures it's visibly a link
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "'Now Playing' was the only option on previous versions and works with all media apps."))
                        Text(String(localized: "Uses macOS Now Playing when the Amazon Music app is the active media source. Playback controls follow the system Now Playing target. Scrubbing the timeline may not work if the Amazon Music app does not support remote seek."))
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            Section {
                Defaults.Toggle(key: .showStandardMediaControls) {
                    Text("Show media controls in Dynamic Island")
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Show media controls in Dynamic Island"))

                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) {
                    Text("Auto-hide inactive notch media player")
                }
                .disabled(enableMinimalisticUI || !showStandardMediaControls)
                .settingsHighlight(id: highlightID("Auto-hide inactive notch media player"))

                if enableMinimalisticUI {
                    Text("Disable Minimalistic UI to configure the standard notch media controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if standardControlsSuppressed {
                    Text("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !autoHideInactiveNotchMediaPlayer {
                    Text("When disabled, the notch music player stays visible with placeholder metadata even when playback is inactive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Dynamic Island Visibility")
            }
            Section {
                Defaults.Toggle(key: .showShuffleAndRepeat) {
                    HStack {
                        Text("Enable customizable controls")
                        customBadge(text: "Beta")
                    }
                }
                if showShuffleAndRepeat {
                    Defaults.Toggle(key: .showMediaOutputControl) {
                        Text("Show \"Change Media Output\" control")
                    }
                    .settingsHighlight(id: highlightID("Show Change Media Output control"))
                    .help("Adds the AirPlay/route picker button back to the customizable controls palette.")
                    MusicSlotConfigurationView()
                } else {
                    Text("Turn on customizable controls to rearrange media buttons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Media controls")
            }

            Section(header: Text("Lock Screen Media")) {
                Defaults.Toggle(key: .lockScreenMusicAlbumParallaxEnabled) {
                    Text("Enable album art parallax")
                }
                .settingsHighlight(id: highlightID("Enable album art parallax"))
                Text("Applies the notch-style parallax effect to the lock screen media widget album art.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if musicControlWindowEnabled {
                Section {
                    Picker("Skip buttons", selection: $musicSkipBehavior) {
                        ForEach(MusicSkipBehavior.allCases) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Skip buttons"))

                    Text(musicSkipBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Floating window panel skip behaviour")
                }
            }
            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .disabled(standardControlsSuppressed)
                .help(standardControlsSuppressed ? "Standard notch media controls are hidden while this toggle is off." : "")
                Defaults.Toggle(key: .musicControlWindowEnabled) {
                    Text("Show floating media controls")
                }
                .disabled(!coordinator.musicLiveActivityEnabled || standardControlsSuppressed)
                .help("Displays play/pause and skip buttons beside the notch while music is active. Disabled by default.")
                Toggle("Enable sneak peek", isOn: $enableSneakPeek)
                Toggle("Show sneak peek on playback changes", isOn: $showSneakPeekOnTrackChange)
                    .disabled(!enableSneakPeek)
                Defaults.Toggle(key: .enableLyrics) {
                    Text("Enable lyrics")
                }
                .settingsHighlight(id: highlightID("Enable lyrics"))
                
                //Parallax Effect Intensity to control how much parallax is wanted
                Slider(value: $parallaxEffectIntensity, in: 0...12, step: 1.0) {
                    HStack {
                        Text("Parallax Effect Intensity")
                        Spacer()
                        Text("\(parallaxEffectIntensity, specifier: "%0.1f")")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Enable album art parallax effect"))
                
                Picker("Sneak Peek Style", selection: $sneakPeekStyles){
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .disabled(!enableSneakPeek)
                .settingsHighlight(id: highlightID("Sneak Peek Style"))

                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }

            Section {
                Defaults.Toggle(key: .enableRealTimeWaveform) {
                    HStack {
                        Text("Enable real-time waveform")
                        customBadge(text: "Beta")
                    }
                }
                .settingsHighlight(id: highlightID("Enable real-time waveform"))
            } header: {
                Text("Music Visualizer")
            } footer: {
                Text("When enabled, the music visualizer displays real-time audio spectrum data synced to your music. Requires macOS 14.2+ and uses minimal CPU/GPU resources via the Accelerate framework.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Show lock screen media panel")
                }
                Defaults.Toggle(key: .lockScreenShowAppIcon) {
                    Text("Show media app icon")
                }
                .disabled(!enableLockScreenMediaWidget)
                if isAppleMusicActive {
                    Defaults.Toggle(key: .lockScreenMusicMergedAirPlayOutput) {
                        Text("Show merged AirPlay and output devices")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Show merged AirPlay and output devices"))
                }
                Defaults.Toggle(key: .lockScreenPanelShowsBorder) {
                    Text("Show panel border")
                }
                .disabled(!enableLockScreenMediaWidget)
                if lockScreenGlassCustomizationMode == .customLiquid {
                    Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                        Text("Use enhanced liquid border")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                }
                if lockScreenGlassCustomizationMode == .customLiquid {
                    customLiquidBlurRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else if lockScreenGlassStyle == .frosted {
                    Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                        Text("Enable media panel blur")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else {
                    unavailableBlurRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                }
            } header: {
                Text("Lock Screen Integration")
            } footer: {
                Text("These controls mirror the Lock Screen tab so you can tune the media overlay while focusing on playback settings.")
            }
            .disabled(!showStandardMediaControls)
            .opacity(showStandardMediaControls ? 1 : 0.5)

            Picker(selection: $hideNotchOption, label:
                    HStack {
                Text("Hide DynamicIsland Options")
                customBadge(text: "Beta")
            }) {
                Text("Always hide in fullscreen").tag(HideNotchOption.always)
                Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                Text("Never hide").tag(HideNotchOption.never)
            }
            .onChange(of: hideNotchOption) {
                Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
            }
        }
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }

    private var unavailableBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Only applies when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var customLiquidBlurRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Custom liquid glass already renders with Apple's liquid material, so this option is managed automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.reminderLeadTime) var reminderLeadTime
    @Default(.reminderSneakPeekDuration) var reminderSneakPeekDuration
    @Default(.enableLockScreenReminderWidget) var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) var lockScreenReminderChipStyle
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.showFullEventTitles) var showFullEventTitles
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.enableThirdPartyCalendarApp) private var enableThirdPartyCalendarApp
    @Default(.selectedCalendarApp) private var selectedCalendarApp
    @Default(.fantasticalDefaultView) private var fantasticalDefaultView

    private func highlightID(_ title: String) -> String {
        SettingsTab.calendar.highlightID(for: title)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return "15 mins"
            case .mins30: return "30 mins"
            case .hour1: return "1 hour"
            case .hours3: return "3 hours"
            case .hours6: return "6 hours"
            case .hours12: return "12 hours"
            case .restOfDay: return "Rest of the day"
            case .allTime: return "All time"
            }
        }
    }

    var body: some View {
        Form {
            if !calendarManager.hasCalendarAccess || !calendarManager.hasReminderAccess {
                Text("Calendar or Reminder access is denied. Please enable it in System Settings.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()

                HStack {
                    Button("Request Access") {
                        Task {
                            await calendarManager.checkCalendarAuthorization()
                            await calendarManager.checkReminderAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open System Settings") {
                        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                }
            } else {
                // Permissions status
                Section(header: Text("Permissions")) {
                    HStack {
                        Text("Calendars")
                        Spacer()
                        Text(statusText(for: calendarManager.calendarAuthorizationStatus))
                            .foregroundColor(color(for: calendarManager.calendarAuthorizationStatus))
                    }
                    HStack {
                        Text("Reminders")
                        Spacer()
                        Text(statusText(for: calendarManager.reminderAuthorizationStatus))
                            .foregroundColor(color(for: calendarManager.reminderAuthorizationStatus))
                    }
                }

                Defaults.Toggle(key: .showCalendar) {
                    Text("Show calendar")
                }
                .settingsHighlight(id: highlightID("Show calendar"))

                Section(header: Text("Event List")) {
                    Toggle("Hide completed reminders", isOn: $hideCompletedReminders)
                        .settingsHighlight(id: highlightID("Hide completed reminders"))
                    Toggle("Show full event titles", isOn: $showFullEventTitles)
                        .settingsHighlight(id: highlightID("Show full event titles"))
                    Toggle("Auto-scroll to next event", isOn: $autoScrollToNextEvent)
                        .settingsHighlight(id: highlightID("Auto-scroll to next event"))
                }

                Section(header: Text("All-Day Events")) {
                    Toggle("Hide all-day events", isOn: $hideAllDayEvents)
                        .settingsHighlight(id: highlightID("Hide all-day events"))
                        .disabled(!showCalendar)

                    Text("Turn this off to include all-day entries in the notch calendar and reminder live activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(header: Text("Reminder Live Activity")) {
                    Defaults.Toggle(key: .enableReminderLiveActivity) {
                        Text("Enable reminder live activity")
                    }
                    .settingsHighlight(id: highlightID("Enable reminder live activity"))

                    Picker("Countdown style", selection: $reminderPresentationStyle) {
                        ForEach(ReminderPresentationStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!enableReminderLiveActivity)
                    .settingsHighlight(id: highlightID("Countdown style"))

                    HStack {
                        Text("Notify before")
                        Slider(
                            value: Binding(
                                get: { Double(reminderLeadTime) },
                                set: { reminderLeadTime = Int($0) }
                            ),
                            in: 1...60,
                            step: 1
                        )
                        .disabled(!enableReminderLiveActivity)
                        Text("\(reminderLeadTime) min")
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }

                    HStack {
                        Text("Sneak peek duration")
                        Slider(
                            value: $reminderSneakPeekDuration,
                            in: 3...20,
                            step: 1
                        )
                        .disabled(!enableReminderLiveActivity)
                        Text("\(Int(reminderSneakPeekDuration)) s")
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }

                Section(header: Text("Lock Screen Reminder Widget")) {
                    Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                        Text("Show lock screen reminder")
                    }
                    .settingsHighlight(id: highlightID("Show lock screen reminder"))

                    Picker("Chip color", selection: $lockScreenReminderChipStyle) {
                        ForEach(LockScreenReminderChipStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!enableLockScreenReminderWidget || !enableReminderLiveActivity)
                    .settingsHighlight(id: highlightID("Chip color"))
                }

                Section(
                    header: Text("Calendar Widget"),
                    footer: Text("Displays your next upcoming calendar event above or below the weather capsule. Calendar selection here is independent from the Dynamic Island calendar filter.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                ) {
                    Defaults.Toggle(key: .lockScreenShowCalendarEvent) {
                        Text("Show next calendar event")
                    }
                    .settingsHighlight(id: highlightID("Show next calendar event"))

                    LabeledContent("Show events within the next") {
                        HStack {
                            Spacer(minLength: 0)
                            Picker("", selection: $lockScreenCalendarEventLookaheadWindow) {
                                ForEach(CalendarLookaheadOption.allCases) { option in
                                    Text(option.title).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show events within the next"))

                    Toggle("Show events from all calendars", isOn: Binding(
                        get: { lockScreenCalendarSelectionMode == "all" },
                        set: { useAll in
                            if useAll {
                                lockScreenCalendarSelectionMode = "all"
                            } else {
                                lockScreenCalendarSelectionMode = "selected"
                                lockScreenSelectedCalendarIDs = Set(calendarManager.eventCalendars.map { $0.id })
                            }
                        }
                    ))
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show events from all calendars"))

                    if lockScreenCalendarSelectionMode != "all" {
                        HStack {
                            Spacer()
                            Button("Deselect All") {
                                lockScreenSelectedCalendarIDs = []
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                                Toggle(isOn: Binding(
                                    get: { lockScreenSelectedCalendarIDs.contains(calendar.id) },
                                    set: { isOn in
                                        if isOn {
                                            lockScreenSelectedCalendarIDs.insert(calendar.id)
                                        } else {
                                            lockScreenSelectedCalendarIDs.remove(calendar.id)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(calendar.color))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 2)
                        .disabled(!lockScreenShowCalendarEvent)
                    }

                    Defaults.Toggle(key: .lockScreenShowCalendarCountdown) {
                        Text("Show countdown")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show countdown"))

                    Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) {
                        Text("Show event for entire duration")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show event for entire duration"))
                    .onChange(of: Defaults[.lockScreenShowCalendarEventEntireDuration]) { _, newValue in
                        if newValue {
                            Defaults[.lockScreenShowCalendarEventAfterStartEnabled] = false
                        }
                    }

                    Defaults.Toggle(key: .lockScreenShowCalendarEventAfterStartEnabled) {
                        Text("Hide active event and show next upcoming event")
                    }
                    .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration)
                    .settingsHighlight(id: highlightID("Hide active event and show next upcoming event"))

                    LabeledContent("Show event after it starts") {
                        HStack {
                            Spacer(minLength: 0)
                            Picker("", selection: $lockScreenShowCalendarEventAfterStartWindow) {
                                Text("1 min").tag("1m")
                                Text("5 mins").tag("5m")
                                Text("10 mins").tag("10m")
                                Text("15 mins").tag("15m")
                                Text("30 mins").tag("30m")
                                Text("45 mins").tag("45m")
                                Text("1 hour").tag("1h")
                                Text("2 hours").tag("2h")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration || !lockScreenShowCalendarEventAfterStartEnabled)

                    Text("Turn off 'Show event for entire duration' to use the post-start duration option.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) {
                        Text("Show time remaining")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show time remaining"))

                    Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) {
                        Text("Show start time after event begins")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show start time after event begins"))
                }
                
                // MARK: - Third-party Calendar Integration
                Section {
                    Defaults.Toggle(key: .enableThirdPartyCalendarApp) {
                        HStack {
                            Image(systemName: "ellipsis.calendar")
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                            Text("Enable third-party calendar app launch")
                        }
                    }
                    .settingsHighlight(id: highlightID("Enable third-party calendar app launch"))
                    
                    if enableThirdPartyCalendarApp {
                        Picker("Calendar App", selection: $selectedCalendarApp) {
                            ForEach(ThirdPartyCalendarApp.allCases) { app in
                                HStack {
                                    AppIconImage(
                                        bundleIdentifiers: app.bundleIdentifiers,
                                        symbolFallback: app.fallbackIconName,
                                        symbolColor: app.fallbackIconColor
                                    )
                                    Text(app.displayName)
                                }
                                .tag(app)
                            }
                        }
                        .settingsHighlight(id: highlightID("Calendar App"))
                        
                        if selectedCalendarApp == .fantastical {
                            Picker("Default View", selection: $fantasticalDefaultView) {
                                ForEach(FantasticalViewStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .settingsHighlight(id: highlightID("Fantastical Default View"))
                        }
                    }
                } header: {
                    Text("Third-party Calendar Integration")
                } footer: {
                    Text("When enabled, clicking on calendar events will open the selected third-party calendar app instead of Apple Calendar.")
                }

                Section(header: Text("Select Calendars")) {
                    let grouped = Dictionary(grouping: calendarManager.allCalendars, by: \.accountName)
                    let sortedAccounts = grouped.keys.sorted()

                    ForEach(sortedAccounts, id: \.self) { account in
                        let accountCalendars = grouped[account] ?? []
                        let allAccountSelected = accountCalendars.allSatisfy { calendarManager.getCalendarSelected($0) }

                        Section(header: HStack {
                            Text(account)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { allAccountSelected },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarsSelected(accountCalendars, isSelected: isSelected)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(!showCalendar)
                        }) {
                            ForEach(accountCalendars, id: \.id) { calendar in
                                Toggle(isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(calendar.color))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .disabled(!showCalendar)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
        .navigationTitle("Calendar")
    }

    private func statusText(for status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess, .authorized: return String(localized: "Full Access")
        case .writeOnly: return String(localized: "Write Only")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted")
        case .notDetermined: return String(localized: "Not Determined")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private func color(for status: EKAuthorizationStatus) -> Color {
        switch status {
        case .fullAccess, .authorized: return .green
        case .writeOnly: return .yellow
        case .denied, .restricted: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Release name")
                        Spacer()
                        Text(Defaults[.releaseName])
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                UpdaterSettingsView(updater: updaterController.updater)

                HStack(spacing: 30) {
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(sponsorPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Donate")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                    Button {
                        NSWorkspace.shared.open(productPage)
                    } label: {
                        VStack(spacing: 5) {
                            Image("Github")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18)
                            Text("GitHub")
                                .foregroundStyle(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(PlainButtonStyle())
                Text("Your support funds software development learning for students in 9th–12th grade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with ❤️ by Ebullioscopic")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.regularMaterial)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

private extension DevicesSettingsView {
    enum BluetoothHUDIconStyle: String {
        case symbol
        case threeD

        var title: String {
            switch self {
            case .symbol:
                return "Symbol"
            case .threeD:
                return "3D"
            }
        }
    }

    struct BluetoothHUDIconStyleCard: View {
        let style: BluetoothHUDIconStyle
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    preview
                }
                .frame(width: 90, height: 64)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }

                Text(style.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
            .onTapGesture { action() }
        }

        private var preview: some View {
            Group {
                switch style {
                case .symbol:
                    Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                case .threeD:
                    if let url = Bundle.main.url(
                        forResource: BluetoothAudioDeviceType.airpods.inlineHUDAnimationBaseName,
                        withExtension: "mov"
                    ) {
                        SettingsLoopingVideoIcon(url: url, size: CGSize(width: 28, height: 28))
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }

        private var backgroundColor: Color {
            if isSelected { return Color.accentColor.opacity(0.12) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

private struct SettingsLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: SettingsLoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = SettingsLoopingPlayerController(url: url, autoPlay: true)
            layer.player = controller?.player
        }
    }
}

private final class SettingsLoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, autoPlay: Bool = true) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        if autoPlay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

struct Shelf: View {
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection
    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.shelf.highlightID(for: title)
    }

    var body: some View {
        Form {
            if !canEnableShelf || !fullDiskAccessPermission.isAuthorized {
                Section {
                    if !canEnableShelf {
                        SettingsPermissionCallout(
                            title: "Additional folder access required",
                            message: "Enable Full Disk Access, or grant access to both Documents and Downloads folders to use Shelf.",
                            icon: "folder.badge.questionmark",
                            iconColor: .orange,
                            requestButtonTitle: "Request Folder Access",
                            openSettingsButtonTitle: "Open Privacy & Security",
                            requestAction: { shelfFolderAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { shelfFolderAccessPermission.openSystemSettings() }
                        )
                    }

                    if !fullDiskAccessPermission.isAuthorized {
                        SettingsPermissionCallout(
                            title: "Full Disk Access for global mode",
                            message: "Without Full Disk Access, Shelf can only read files from Documents and Downloads. Grant Full Disk Access to make Shelf work globally.",
                            icon: "externaldrive.fill",
                            iconColor: .purple,
                            requestButtonTitle: "Request Full Disk Access",
                            openSettingsButtonTitle: "Open Privacy & Security",
                            requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                            openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                        )
                    }
                } header: {
                    Text("Permissions")
                }
            }

            Section {
                Defaults.Toggle(key: .dynamicShelf) {
                    Text("Enable shelf")
                }
                .disabled(!canEnableShelf)
                .settingsHighlight(id: highlightID("Enable shelf"))

                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf tab by default if items added")
                }
                .settingsHighlight(id: highlightID("Open shelf tab by default if items added"))

                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .settingsHighlight(id: highlightID("Expanded drag detection area"))

                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                .settingsHighlight(id: highlightID("Copy items on drag"))

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }
                .settingsHighlight(id: highlightID("Remove from shelf after dragging"))
            } header: {
                HStack {
                    Text("General")
                }
            }

            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            QuickShareProviderIconImage(provider: provider, size: 16)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                .settingsHighlight(id: highlightID("Quick Share Service"))

                if let selectedProvider {
                    HStack {
                        QuickShareProviderIconImage(provider: selectedProvider, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Drag files onto the shelf or click the shelf button to pick files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if quickShareProvider == "LocalSend" {
                LocalSendSettingsSection(highlightID: highlightID)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

private struct LocalSendSettingsSection: View {
    let highlightID: (String) -> String
    
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant
    
    var body: some View {
        Section {
            Picker("Device Picker Style", selection: $glassMode) {
                ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            
            if glassMode == .customLiquid {
                Picker("Liquid Glass Variant", selection: $liquidGlassVariant) {
                    ForEach(LiquidGlassVariant.allCases) { variant in
                        Text("Variant \(variant.rawValue)").tag(variant)
                    }
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("LocalSend Device Picker")
        } footer: {
            Text("Customize the appearance of the LocalSend device selection popup that appears when you drop files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenRecordingDetection) {
                    Text("Enable Screen Recording Detection")
                }
                .settingsHighlight(id: highlightID("Enable Screen Recording Detection"))

                Defaults.Toggle(key: .showRecordingIndicator) {
                    Text("Show Recording Indicator")
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Show Recording Indicator"))

                if recordingManager.isMonitoring {
                    HStack {
                        Text("Detection Status")
                        Spacer()
                        if recordingManager.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Recording Detected")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("Active - No Recording")
                                .foregroundColor(.green)
                        }
                    }
                }
            } header: {
                Text("Screen Recording")
            } footer: {
                Text("Uses event-driven private API for real-time screen recording detection")
            }

            Section {
                if !fullDiskAccessPermission.isAuthorized {
                    SettingsPermissionCallout(
                        title: String(localized: "Custom Focus metadata"),
                        message: String(localized: "Full Disk Access unlocks custom Focus icons, colors, and labels. Standard Focus detection still works without it—grant access only if you need personalized indicators."),
                        icon: "externaldrive.fill",
                        iconColor: .purple,
                        requestButtonTitle: String(localized: "Request Full Disk Access"),
                        openSettingsButtonTitle: String(localized: "Open Privacy & Security"),
                        requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                        openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                    )
                }

                Defaults.Toggle(key: .enableDoNotDisturbDetection) {
                    Text("Enable Focus Detection")
                }
                .settingsHighlight(id: highlightID("Enable Focus Detection"))

                Defaults.Toggle(key: .showDoNotDisturbIndicator) {
                    Text("Show Focus Indicator")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus Indicator"))

                Defaults.Toggle(key: .showDoNotDisturbLabel) {
                    Text("Show Focus Label")
                }
                .disabled(!enableDoNotDisturbDetection || focusIndicatorNonPersistent)
                .help(focusIndicatorNonPersistent ? "Labels are forced to compact on/off text while brief toast mode is enabled." : "Show the active Focus name inside the indicator.")
                .settingsHighlight(id: highlightID("Show Focus Label"))

                Defaults.Toggle(key: .focusIndicatorNonPersistent) {
                    Text("Show Focus as brief toast")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus as brief toast"))
                .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")

                if doNotDisturbManager.isMonitoring {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        if doNotDisturbManager.isDoNotDisturbActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                Text(doNotDisturbManager.currentFocusModeName.isEmpty ? "Focus Enabled" : doNotDisturbManager.currentFocusModeName)
                                    .foregroundColor(.purple)
                            }
                        } else {
                            Text("Active - No Focus")
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        Text("Disabled")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                Text("Listens for Focus session changes via distributed notifications")
            }

            Section {
                Defaults.Toggle(key: .enableCapsLockIndicator) {
                    Text("Show Caps Lock Indicator")
                }
                .settingsHighlight(id: highlightID("Show Caps Lock Indicator"))

                Defaults.Toggle(key: .showCapsLockLabel) {
                    Text("Show Caps Lock label")
                }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Show Caps Lock label"))

                Picker("Caps Lock color", selection: $capsLockTintMode) {
                    ForEach(CapsLockIndicatorTintMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Caps Lock color"))
            } header: {
                Text("Caps Lock Indicator")
            } footer: {
                Text("Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls.")
            }

            Section {
                Defaults.Toggle(key: .enableCameraDetection) {
                    Text("Enable Camera Detection")
                }
                .settingsHighlight(id: highlightID("Enable Camera Detection"))
                Defaults.Toggle(key: .enableMicrophoneDetection) {
                    Text("Enable Microphone Detection")
                }
                .settingsHighlight(id: highlightID("Enable Microphone Detection"))

                if privacyManager.isMonitoring {
                    HStack {
                        Text("Camera Status")
                        Spacer()
                        if privacyManager.cameraActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Camera Active")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Microphone Status")
                        Spacer()
                        if privacyManager.microphoneActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: 8)
                                Text("Microphone Active")
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Privacy Indicators")
            } footer: {
                Text("Shows green camera icon and yellow microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs.")
            }

            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .settingsHighlight(id: highlightID("Enable music live activity"))
            } header: {
                Text("Media Live Activity")
            } footer: {
                Text("Use the Media tab to configure sneak peek, lyrics, and floating media controls.")
            }

            Section {
                Defaults.Toggle(key: .enableReminderLiveActivity) {
                    Text("Enable reminder live activity")
                }
                .settingsHighlight(id: highlightID("Enable reminder live activity"))
            } header: {
                Text("Reminder Live Activity")
            } footer: {
                Text("Configure countdown style and lock screen widgets in the Calendar tab.")
            }
        }
        .navigationTitle("Live Activities")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
        }
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.selectedCameraID) var selectedCameraID
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @State private var selectedListVisualizer: CustomVisualizer? = nil

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var appearanceMusicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var appearanceTimerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Settings icon in notch")
                }
                .settingsHighlight(id: highlightID("Settings icon in notch"))
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
                .settingsHighlight(id: highlightID("Corner radius scaling"))
                Defaults.Toggle(key: .useModernCloseAnimation) {
                    Text("Use simpler close animation")
                }
                .settingsHighlight(id: highlightID("Use simpler close animation"))
            } header: {
                Text("General")
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    Picker("Main screen style", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { style in
                            Text(style.localizedName)
                                .tag(style)
                        }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                    Text(externalDisplayStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Display Style")
                }
            }

            notchWidthControls()

            Section {
                if #available(macOS 26.0, *) {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Lock screen material"))
                } else {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Lock screen material"))
                    Text("Liquid Glass requires macOS 26 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if lockScreenGlassStyle == .liquid {
                    Picker("Lock screen glass mode", selection: $lockScreenGlassCustomizationMode) {
                        ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Lock screen glass mode"))

                    if lockScreenGlassCustomizationMode == .customLiquid {
                        Text("Pick per-widget liquid-glass variants below. Changes mirror the Lock Screen tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Music panel variant")
                                Spacer()
                                Text("v\(lockScreenMusicLiquidGlassVariant.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: appearanceMusicVariantBinding, in: liquidVariantRange, step: 1)

                            LockScreenGlassVariantPreviewCell(variant: $lockScreenMusicLiquidGlassVariant)
                                .padding(.top, 6)
                        }
                        .settingsHighlight(id: highlightID("Music panel variant (appearance)"))
                        .disabled(!enableLockScreenMediaWidget)
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.4)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Timer widget variant")
                                Spacer()
                                Text("v\(lockScreenTimerLiquidGlassVariant.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: appearanceTimerVariantBinding, in: liquidVariantRange, step: 1)
                        }
                        .settingsHighlight(id: highlightID("Timer widget variant (appearance)"))
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.4)
                    }
                } else {
                    Text("Custom Liquid settings require the Liquid Glass material.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Lock Screen Glass")
            } footer: {
                Text("Configure lock screen materials from the Appearance tab. Custom Liquid unlocks variant sliders for both widgets whenever Liquid Glass is selected.")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Enable colored spectrograms")
                }
                .settingsHighlight(id: highlightID("Enable colored spectrograms"))
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Enable colored spectograms")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                .settingsHighlight(id: highlightID("Enable blur effect behind album art"))
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
                .settingsHighlight(id: highlightID("Slider color"))
            } header: {
                Text("Media")
            }

            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Color.accentColor : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable Dynamic mirror")
                }
                .disabled(!checkVideoInput())
                .settingsHighlight(id: highlightID("Enable Dynamic mirror"))
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .settingsHighlight(id: highlightID("Mirror shape"))
                
                if webcamManager.cameraAvailable {
                    Picker("Mirror Camera", selection: $selectedCameraID) {
                        ForEach(webcamManager.availableCameras, id: \.uniqueID) { device in
                            Text(device.localizedName)
                                .tag(device.uniqueID)
                        }
                    }
                    .onChange(of: selectedCameraID) { _, _ in
                        if Defaults[.showMirror] {
                            webcamManager.stopSession()
                            webcamManager.startSession()
                        }
                    }
                    .settingsHighlight(id: highlightID("Mirror Camera"))
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Idle Animation")
                }
                .settingsHighlight(id: highlightID("Idle Animation"))
            } header: {
                HStack {
                    Text("Additional features")
                }
            }

            // MARK: - Custom Idle Animations Section
            IdleAnimationsSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        appIconCard(
                            title: "Default",
                            image: defaultAppIconImage(),
                            isSelected: selectedAppIconID == nil
                        ) {
                            selectedAppIconID = nil
                            applySelectedAppIcon()
                        }

                        ForEach(customAppIcons) { icon in
                            appIconCard(
                                title: icon.name,
                                image: customIconImage(for: icon),
                                isSelected: selectedAppIconID == icon.id.uuidString
                            ) {
                                selectedAppIconID = icon.id.uuidString
                                applySelectedAppIcon()
                            }
                            .contextMenu {
                                Button("Remove") {
                                    removeCustomIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                        handleIconDrop(providers)
                    }

                    HStack(spacing: 8) {
                        Button("Add icon") {
                            iconImportError = nil
                            isIconImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove selected") {
                            if let id = selectedAppIconID,
                               let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                                removeCustomIcon(icon)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAppIconID == nil)
                    }

                    if let iconImportError {
                        Text(iconImportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("App icon"))
            } header: {
                HStack {
                    Text("App icon")
                }
            }
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "Icon import was canceled or failed."
            }
        }
        .navigationTitle("Appearance")
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            iconImportError = "That file could not be loaded as an image."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "Unable to save the icon file."
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        NSApp.applicationIconImage = image
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }

        return false
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        Section {
            let recommendedMin = currentRecommendedMinimumNotchWidth()
            let tabCount = enabledStandardTabCount()
            let dynamicRange = Double(recommendedMin)...900

            let widthBinding = Binding<Double>(
                get: { Double(openNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, dynamicRange.lowerBound), dynamicRange.upperBound)
                    let value = CGFloat(clamped)
                    if openNotchWidth != value {
                        openNotchWidth = value
                    }
                }
            )

            VStack(alignment: .leading, spacing: 10) {
                Slider(
                    value: widthBinding,
                    in: dynamicRange,
                    step: 10
                ) {
                    HStack {
                        Text("Expanded notch width")
                        Spacer()
                        Text("\(Int(openNotchWidth)) px")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Expanded notch width"))

                HStack {
                    Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") enabled · min \(Int(recommendedMin)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Width") {
                        openNotchWidth = recommendedMin
                    }
                    .disabled(abs(openNotchWidth - recommendedMin) < 0.5)
                    .buttonStyle(.bordered)
                }

                let description = enableMinimalisticUI
                ? String(localized: "Width adjustments apply only to the standard notch layout. Disable Minimalistic UI to edit this value.")
                : String(localized: "Recommended minimum width adjusts automatically based on the number of enabled tabs.")

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                enforceMinimumNotchWidth()
            }
        } header: {
            HStack {
                Text("Notch Width")
                customBadge(text: "Beta")
            }
        }
    }

    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }
}

struct LockScreenSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var previewManager = LockScreenWidgetPreviewManager.shared
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.enableLockScreenWeatherWidget) private var enableLockScreenWeatherWidget
    @Default(.enableLockScreenFocusWidget) private var enableLockScreenFocusWidget
    @Default(.lockScreenWeatherWidgetStyle) private var lockScreenWeatherWidgetStyle
    @Default(.lockScreenWeatherProviderSource) private var lockScreenWeatherProviderSource
    @Default(.lockScreenWeatherTemperatureUnit) private var lockScreenWeatherTemperatureUnit
    @Default(.lockScreenBatteryShowsCharging) private var lockScreenWeatherShowsCharging
    @Default(.lockScreenBatteryShowsBatteryGauge) private var lockScreenWeatherShowsBatteryGauge
    @Default(.lockScreenWeatherShowsAQI) private var lockScreenWeatherShowsAQI
    @Default(.lockScreenWeatherShowsSunrise) private var lockScreenWeatherShowsSunrise
    @Default(.lockScreenWeatherAQIScale) private var lockScreenWeatherAQIScale
    @Default(.enableLockScreenReminderWidget) private var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) private var lockScreenReminderChipStyle
    @Default(.lockScreenReminderWidgetHorizontalAlignment) private var lockScreenReminderWidgetHorizontalAlignment
    @Default(.lockScreenReminderWidgetVerticalOffset) private var lockScreenReminderWidgetVerticalOffset
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.lockScreenMusicMergedAirPlayOutput) private var lockScreenMusicMergedAirPlayOutput
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.lockScreen.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return "15 mins"
            case .mins30: return "30 mins"
            case .hour1: return "1 hour"
            case .hours3: return "3 hours"
            case .hours6: return "6 hours"
            case .hours12: return "12 hours"
            case .restOfDay: return "Rest of the day"
            case .allTime: return "All time"
            }
        }
    }

    private enum ReminderAlignmentOption: String, CaseIterable, Identifiable {
        case leading
        case center
        case trailing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .leading: return "Left"
            case .center: return "Center"
            case .trailing: return "Right"
            }
        }
    }

    private var musicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableLockScreenLiveActivity) {
                    Text("Enable lock screen live activity")
                }
                .settingsHighlight(id: highlightID("Enable lock screen live activity"))
                Defaults.Toggle(key: .enableLockSounds) {
                    Text("Play lock/unlock sounds")
                }
                .settingsHighlight(id: highlightID("Play lock/unlock sounds"))
            } header: {
                Text("Live Activity & Feedback")
            } footer: {
                Text("Controls whether Dynamic Island mirrors lock/unlock events with its own live activity and audible chimes.")
            }

            Section {
                Button(previewManager.isPreviewVisible ? "Hide lock screen preview" : "Preview lock screen widgets") {
                    previewManager.togglePreview()
                }
                .buttonStyle(.borderedProminent)
                .settingsHighlight(id: highlightID("Preview lock screen widgets"))
            } header: {
                Text("Preview")
            } footer: {
                Text("Opens a transparent preview window with mock data that mirrors the current lock screen widget configuration.")
            }

            Section {
                if #available(macOS 26.0, *) {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                } else {
                    Picker("Material", selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .disabled(true)
                    .settingsHighlight(id: highlightID("Material"))
                    Text("Liquid Glass requires macOS 26 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if lockScreenGlassStyle == .liquid {
                    Picker("Glass mode", selection: $lockScreenGlassCustomizationMode) {
                        ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Glass mode"))

                    if lockScreenGlassCustomizationMode == .customLiquid {
                        Text("Use the sliders below to pick unique Apple liquid-glass variants for each widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Custom Liquid settings require the Liquid Glass material.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Lock Screen Glass")
            } footer: {
                Text("Choose the global material mode for lock screen widgets. Custom Liquid unlocks per-widget variant sliders while Standard sticks to the classic frosted/liquid options.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                    Text("Show lock screen media panel")
                }
                .settingsHighlight(id: highlightID("Show lock screen media panel"))
                Defaults.Toggle(key: .lockScreenShowAppIcon) {
                    Text("Show media app icon")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Show media app icon"))
                if isAppleMusicActive {
                    Defaults.Toggle(key: .lockScreenMusicMergedAirPlayOutput) {
                        Text("Show merged AirPlay and output devices")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Show merged AirPlay and output devices"))
                }
                Defaults.Toggle(key: .lockScreenPanelShowsBorder) {
                    Text("Show panel border")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Show panel border"))
                if lockScreenGlassCustomizationMode == .customLiquid {
                    Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                        Text("Use enhanced liquid border")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Use enhanced liquid border"))
                }
                if lockScreenGlassCustomizationMode == .customLiquid {
                    variantSlider(
                        title: "Music panel variant",
                        value: musicVariantBinding,
                        currentValue: lockScreenMusicLiquidGlassVariant.rawValue,
                        isEnabled: enableLockScreenMediaWidget,
                        highlight: highlightID("Music panel variant")
                    )
                } else if lockScreenGlassStyle == .frosted {
                    Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                        Text("Enable media panel blur")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Enable media panel blur"))
                } else {
                    blurSettingUnavailableRow
                        .opacity(enableLockScreenMediaWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Enable media panel blur"))
                }

                if !showStandardMediaControls {
                    Text("Enable Dynamic Island media controls to manage the lock screen panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Media Panel")
            } footer: {
                Text("Enable and style the media controls that appear above the system clock when the screen is locked.")
            }
            .disabled(!showStandardMediaControls)
            .opacity(showStandardMediaControls ? 1 : 0.5)

            Section {
                Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                    Text("Show lock screen timer")
                }
                .settingsHighlight(id: highlightID("Show lock screen timer"))
                Picker("Timer surface", selection: timerSurfaceBinding) {
                    ForEach(LockScreenTimerSurfaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenTimerWidget)
                .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                .settingsHighlight(id: highlightID("Timer surface"))

                if timerGlassModeIsGlass {
                    Picker("Timer glass material", selection: $lockScreenTimerGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .disabled(!enableLockScreenTimerWidget)
                    .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                    .settingsHighlight(id: highlightID("Timer glass material"))

                    if lockScreenTimerGlassStyle == .liquid {
                        Picker("Timer liquid mode", selection: $lockScreenTimerGlassCustomizationMode) {
                            ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                        .settingsHighlight(id: highlightID("Timer liquid mode"))

                        if lockScreenTimerGlassCustomizationMode == .customLiquid {
                            variantSlider(
                                title: "Timer widget variant",
                                value: timerVariantBinding,
                                currentValue: lockScreenTimerLiquidGlassVariant.rawValue,
                                isEnabled: enableLockScreenTimerWidget,
                                highlight: highlightID("Timer widget variant")
                            )
                        }
                    } else {
                        Text("Uses the frosted blur treatment while glass mode is enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Classic mode keeps the original translucent black background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                }
            } header: {
                Text("Timer Widget")
            } footer: {
                Text("Controls the optional timer widget that floats above the media panel, including its classic, frosted, or liquid glass surface independent of the global material setting.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                    Text("Show lock screen weather")
                }
                .settingsHighlight(id: highlightID("Show lock screen weather"))

                if enableLockScreenWeatherWidget {
                    Picker("Layout", selection: $lockScreenWeatherWidgetStyle) {
                        ForEach(LockScreenWeatherWidgetStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Layout"))

                    Picker("Weather data provider", selection: $lockScreenWeatherProviderSource) {
                        ForEach(LockScreenWeatherProviderSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Weather data provider"))

                    Picker("Temperature unit", selection: $lockScreenWeatherTemperatureUnit) {
                        ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .settingsHighlight(id: highlightID("Temperature unit"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsLocation) {
                        Text("Show location label")
                    }
                    .disabled(lockScreenWeatherWidgetStyle == .circular)
                    .settingsHighlight(id: highlightID("Show location label"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) {
                        Text("Show sunrise time")
                    }
                    .disabled(lockScreenWeatherWidgetStyle != .inline)
                    .settingsHighlight(id: highlightID("Show sunrise time"))

                    Defaults.Toggle(key: .lockScreenWeatherShowsAQI) {
                        Text("Show AQI widget")
                    }
                    .disabled(!lockScreenWeatherProviderSource.supportsAirQuality)
                    .settingsHighlight(id: highlightID("Show AQI widget"))

                    if lockScreenWeatherShowsAQI && lockScreenWeatherProviderSource.supportsAirQuality {
                        Picker("Air quality scale", selection: $lockScreenWeatherAQIScale) {
                            ForEach(LockScreenWeatherAirQualityScale.allCases) { scale in
                                Text(scale.displayName).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Air quality scale"))
                    }

                    if !lockScreenWeatherProviderSource.supportsAirQuality {
                        Text("Air quality requires the Open Meteo provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) {
                        Text("Use colored gauges")
                    }
                    .settingsHighlight(id: highlightID("Use colored gauges"))
                }
            } header: {
                Text("Weather Widget")
            } footer: {
                Text("Enable the weather capsule and configure its layout, provider, units, and optional battery/AQI indicators.")
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                    Text("Show lock screen reminder")
                }
                .settingsHighlight(id: highlightID("Show lock screen reminder"))

                Picker("Chip color", selection: $lockScreenReminderChipStyle) {
                    ForEach(LockScreenReminderChipStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenReminderWidget)
                .settingsHighlight(id: highlightID("Chip color"))

                Picker("Alignment", selection: $lockScreenReminderWidgetHorizontalAlignment) {
                    ForEach(ReminderAlignmentOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!enableLockScreenReminderWidget)
                .settingsHighlight(id: highlightID("Reminder alignment"))

                HStack {
                    Text("Vertical offset")
                    Slider(
                        value: $lockScreenReminderWidgetVerticalOffset,
                        in: -160...160,
                        step: 2
                    )
                    .disabled(!enableLockScreenReminderWidget)
                    Text("\(Int(lockScreenReminderWidgetVerticalOffset)) px")
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .settingsHighlight(id: highlightID("Reminder vertical offset"))
            } header: {
                Text("Reminder Widget")
            } footer: {
                Text("Controls the lock screen reminder chip and its positioning.")
            }

            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))

                    if lockScreenWeatherShowsBatteryGauge {
                        Defaults.Toggle(key: .lockScreenBatteryUsesLaptopSymbol) {
                            Text("Use MacBook icon when on battery")
                        }
                        .settingsHighlight(id: highlightID("Use MacBook icon when on battery"))

                        Defaults.Toggle(key: .lockScreenBatteryShowsCharging) {
                            Text("Show charging status")
                        }
                        .settingsHighlight(id: highlightID("Show charging status"))

                        if lockScreenWeatherShowsCharging {
                            Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) {
                                Text("Show charging percentage")
                            }
                            .settingsHighlight(id: highlightID("Show charging percentage"))
                        }

                        Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) {
                            Text("Show Bluetooth battery")
                        }
                        .settingsHighlight(id: highlightID("Show Bluetooth battery"))
                    }
                } header: {
                    Text("Battery Widget")
                } footer: {
                    Text("Enable the battery capsule and configure its layout.")
                }
            }

            Section {
                Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                    Text("Show focus widget")
                }
                .settingsHighlight(id: highlightID("Show focus widget"))
            } header: {
                Text("Focus Widget")
            } footer: {
                Text("Displays the current Focus state above the weather capsule whenever Focus detection is enabled.")
            }

            Section {
                Defaults.Toggle(key: .lockScreenShowCalendarEvent) {
                    Text("Show next calendar event")
                }
                .settingsHighlight(id: highlightID("Show next calendar event"))

                LabeledContent("Show events within the next") {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $lockScreenCalendarEventLookaheadWindow) {
                            ForEach(CalendarLookaheadOption.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show events within the next"))

                Toggle("Show events from all calendars", isOn: Binding(
                    get: { lockScreenCalendarSelectionMode == "all" },
                    set: { useAll in
                        if useAll {
                            lockScreenCalendarSelectionMode = "all"
                        } else {
                            lockScreenCalendarSelectionMode = "selected"
                            lockScreenSelectedCalendarIDs = Set(calendarManager.eventCalendars.map { $0.id })
                        }
                    }
                ))
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show events from all calendars"))

                if lockScreenCalendarSelectionMode != "all" {
                    HStack {
                        Spacer()
                        Button("Deselect All") {
                            lockScreenSelectedCalendarIDs = []
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(isOn: Binding(
                                get: { lockScreenSelectedCalendarIDs.contains(calendar.id) },
                                set: { isOn in
                                    if isOn {
                                        lockScreenSelectedCalendarIDs.insert(calendar.id)
                                    } else {
                                        lockScreenSelectedCalendarIDs.remove(calendar.id)
                                    }
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(calendar.color))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 2)
                    .disabled(!lockScreenShowCalendarEvent)
                }

                Defaults.Toggle(key: .lockScreenShowCalendarCountdown) {
                    Text("Show countdown")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show countdown"))

                Defaults.Toggle(key: .lockScreenShowCalendarEventEntireDuration) {
                    Text("Show event for entire duration")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show event for entire duration"))
                .onChange(of: Defaults[.lockScreenShowCalendarEventEntireDuration]) { _, newValue in
                    if newValue {
                        Defaults[.lockScreenShowCalendarEventAfterStartEnabled] = false
                    }
                }

                Defaults.Toggle(
                    "Hide active event and show next upcoming event",
                    key: .lockScreenShowCalendarEventAfterStartEnabled
                )
                .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration)
                .settingsHighlight(id: highlightID("Hide active event and show next upcoming event"))

                LabeledContent("Show event after it starts") {
                    HStack {
                        Spacer(minLength: 0)
                        Picker("", selection: $lockScreenShowCalendarEventAfterStartWindow) {
                            Text("1 min").tag("1m")
                            Text("5 mins").tag("5m")
                            Text("10 mins").tag("10m")
                            Text("15 mins").tag("15m")
                            Text("30 mins").tag("30m")
                            Text("45 mins").tag("45m")
                            Text("1 hour").tag("1h")
                            Text("2 hours").tag("2h")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .disabled(!lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration || !lockScreenShowCalendarEventAfterStartEnabled)

                Text("Turn off 'Show event for entire duration' to use the post-start duration option.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) {
                    Text("Show time remaining")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show time remaining"))

                Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) {
                    Text("Show start time after event begins")
                }
                .disabled(!lockScreenShowCalendarEvent)
                .settingsHighlight(id: highlightID("Show start time after event begins"))
            } header: {
                Text("Calendar Widget")
            } footer: {
                Text("Displays your next upcoming calendar event above or below the weather capsule. Calendar selection here is independent from the Dynamic Island calendar filter.")
            }

            LockScreenPositioningControls()

            Section {
                Button("Copy Latest Crash Report") {
                    copyLatestCrashReport()
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Collect the latest crash report to share with the developer when reporting lock screen or overlay issues.")
            }
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .navigationTitle("Lock Screen")
    }
}

extension LockScreenSettings {
    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }

    private var blurSettingUnavailableRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enable media panel blur")
                .foregroundStyle(.secondary)
            Text("Only available when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func variantSlider(
        title: String,
        value: Binding<Double>,
        currentValue: Int,
        isEnabled: Bool,
        highlight: String,
        preview: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("v\(currentValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: liquidVariantRange, step: 1)

            if let preview {
                preview
                    .padding(.top, 6)
            }
        }
        .settingsHighlight(id: highlight)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct LockScreenGlassVariantPreviewCell: View {
    @Binding var variant: LiquidGlassVariant

    private let cornerRadius: CGFloat = 16
    private let previewCornerRadius: CGFloat = 14
    private let previewSize = CGSize(width: 190, height: 96)

    var body: some View {
        ZStack {
            Image("glassdesktop")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            liquidGlassPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 6)
        .allowsHitTesting(false)
        .onAppear {
            Logger.log("Lock screen glass preview appeared (variant v\(variant.rawValue))", category: .performance)
        }
        .onDisappear {
            Logger.log("Lock screen glass preview disappeared", category: .performance)
        }
        .onChange(of: variant) { _, newValue in
            Logger.log("Lock screen glass preview variant changed to v\(newValue.rawValue)", category: .performance)
        }
    }

    private var liquidGlassPreview: some View {
        LiquidGlassBackground(
            variant: variant,
            cornerRadius: previewCornerRadius
        ) {
            Color.white.opacity(0.04)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}

private struct LockScreenPositioningControls: View {
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenMusicVerticalOffset) private var musicOffset
    @Default(.lockScreenTimerVerticalOffset) private var timerOffset
    @Default(.lockScreenMusicPanelWidth) private var musicWidth
    @Default(.lockScreenTimerWidgetWidth) private var timerWidth
    private let offsetRange: ClosedRange<Double> = -160...160
    private let musicWidthRange: ClosedRange<Double> = 320...Double(LockScreenMusicPanel.defaultCollapsedWidth)
    private let timerWidthRange: ClosedRange<Double> = 320...LockScreenTimerWidget.defaultWidth

    var body: some View {
        Section {
            let weatherBinding = Binding<Double>(
                get: { weatherOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if weatherOffset != clampedValue {
                        weatherOffset = clampedValue
                    }
                    propagateWeatherOffsetChange(animated: false)
                }
            )

            let timerBinding = Binding<Double>(
                get: { timerOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if timerOffset != clampedValue {
                        timerOffset = clampedValue
                    }
                    propagateTimerOffsetChange(animated: false)
                }
            )

            let musicBinding = Binding<Double>(
                get: { musicOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if musicOffset != clampedValue {
                        musicOffset = clampedValue
                    }
                    propagateMusicOffsetChange(animated: false)
                }
            )

            let musicWidthBinding = Binding<Double>(
                get: { musicWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: musicWidthRange)
                    if musicWidth != clampedValue {
                        musicWidth = clampedValue
                        propagateMusicWidthChange(animated: false)
                    }
                }
            )

            let timerWidthBinding = Binding<Double>(
                get: { timerWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: timerWidthRange)
                    if timerWidth != clampedValue {
                        timerWidth = clampedValue
                        propagateTimerWidthChange(animated: false)
                    }
                }
            )

            LockScreenPositioningPreview(
                weatherOffset: weatherBinding,
                timerOffset: timerBinding,
                musicOffset: musicBinding,
                musicWidth: musicWidthBinding,
                timerWidth: timerWidthBinding
            )
            .frame(height: 260)
            .padding(.vertical, 8)

            HStack(alignment: .top, spacing: 24) {
                offsetColumn(
                    title: String(localized: "Weather"),
                    value: weatherOffset,
                    resetTitle: String(localized: "Reset Weather"),
                    resetAction: resetWeatherOffset
                )

                Divider()
                    .frame(height: 64)

                offsetColumn(
                    title: String(localized: "Timer"),
                    value: timerOffset,
                    resetTitle: String(localized: "Reset Timer"),
                    resetAction: resetTimerOffset
                )

                Divider()
                    .frame(height: 64)

                offsetColumn(
                    title: String(localized: "Music"),
                    value: musicOffset,
                    resetTitle: String(localized: "Reset Music"),
                    resetAction: resetMusicOffset
                )

                Spacer()
            }

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 16) {
                widthSlider(
                    title: String(localized: "Media Panel Width"),
                    value: musicWidthBinding,
                    range: musicWidthRange,
                    resetTitle: String(localized: "Reset Media Width"),
                    resetAction: resetMusicWidth,
                    helpText: String(localized: "Shrinks the lock screen media panel while keeping the expanded view full width.")
                )

                widthSlider(
                    title: String(localized: "Timer Widget Width"),
                    value: timerWidthBinding,
                    range: timerWidthRange,
                    resetTitle: String(localized: "Reset Timer Width"),
                    resetAction: resetTimerWidth,
                    helpText: String(localized: "Adjusts the lock screen timer widget width without affecting button sizing.")
                )
            }
        } header: {
            Text("Lock Screen Positioning")
        } footer: {
            Text("Drag the previews to adjust vertical placement. Positive values lift the panel; negative values lower it. Use the width sliders below to narrow the media and timer widgets without exceeding their default size. Changes apply instantly while the widgets are visible.")
                .textCase(nil)
        }
    }

    private func clampOffset(_ value: Double) -> Double {
        min(max(value, offsetRange.lowerBound), offsetRange.upperBound)
    }

    private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func resetWeatherOffset() {
        weatherOffset = 0
        propagateWeatherOffsetChange(animated: true)
    }

    private func resetTimerOffset() {
        timerOffset = 0
        propagateTimerOffsetChange(animated: true)
    }

    private func resetMusicOffset() {
        musicOffset = 0
        propagateMusicOffsetChange(animated: true)
    }

    private func resetMusicWidth() {
        musicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
        propagateMusicWidthChange(animated: true)
    }

    private func resetTimerWidth() {
        timerWidth = LockScreenTimerWidget.defaultWidth
        propagateTimerWidthChange(animated: true)
    }

    private func propagateWeatherOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateTimerOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateMusicOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateMusicWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateTimerWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetPanelManager.shared.refreshPosition(animated: animated)
        }
    }

    @ViewBuilder
    private func offsetColumn(title: String, value: Double, resetTitle: String, resetAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) Offset")
                .font(.subheadline.weight(.semibold))

            Text("\(formattedPoints(value)) pt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(resetTitle) {
                resetAction()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func widthSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        resetTitle: String,
        resetAction: @escaping () -> Void,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedWidth(value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)

            HStack(alignment: .top) {
                Button(resetTitle) {
                    resetAction()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func formattedPoints(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    private func formattedWidth(_ value: Double) -> String {
        String(format: "%.0f pt", value)
    }
}

private struct LockScreenPositioningPreview: View {
    @Binding var weatherOffset: Double
    @Binding var timerOffset: Double
    @Binding var musicOffset: Double
    @Binding var musicWidth: Double
    @Binding var timerWidth: Double

    @State private var weatherStartOffset: Double = 0
    @State private var timerStartOffset: Double = 0
    @State private var musicStartOffset: Double = 0
    @State private var isWeatherDragging = false
    @State private var isTimerDragging = false
    @State private var isMusicDragging = false

    private let offsetRange: ClosedRange<Double> = -160...160

    var body: some View {
        GeometryReader { geometry in
            let screenPadding: CGFloat = 26
            let screenCornerRadius: CGFloat = 28
            let screenRect = CGRect(
                x: screenPadding,
                y: screenPadding,
                width: geometry.size.width - (screenPadding * 2),
                height: geometry.size.height - (screenPadding * 2)
            )
            let centerX = screenRect.midX
            let weatherBaseY = screenRect.minY + (screenRect.height * 0.28)
            let timerBaseY = screenRect.minY + (screenRect.height * 0.5)
            let musicBaseY = screenRect.minY + (screenRect.height * 0.78)
            let weatherSize = CGSize(width: screenRect.width * 0.42, height: screenRect.height * 0.22)
            let defaultMusicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
            let musicWidthScale = CGFloat(musicWidth / defaultMusicWidth)
            let timerWidthScale = CGFloat(timerWidth / LockScreenTimerWidget.defaultWidth)
            let timerSize = CGSize(
                width: (screenRect.width * 0.5) * timerWidthScale,
                height: screenRect.height * 0.2
            )
            let musicSize = CGSize(
                width: (screenRect.width * 0.56) * musicWidthScale,
                height: screenRect.height * 0.34
            )

            ZStack {
                RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .frame(width: screenRect.width, height: screenRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 18)
                    .position(x: screenRect.midX, y: screenRect.midY)

                weatherPanel(size: weatherSize)
                    .position(x: centerX, y: weatherBaseY - CGFloat(weatherOffset))
                    .gesture(weatherDragGesture(in: screenRect, baseY: weatherBaseY, panelSize: weatherSize))

                timerPanel(size: timerSize)
                    .position(x: centerX, y: timerBaseY - CGFloat(timerOffset))
                    .gesture(timerDragGesture(in: screenRect, baseY: timerBaseY, panelSize: timerSize))

                musicPanel(size: musicSize)
                    .position(x: centerX, y: musicBaseY - CGFloat(musicOffset))
                    .gesture(musicDragGesture(in: screenRect, baseY: musicBaseY, panelSize: musicSize))
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: weatherOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicWidth)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerWidth)
    }

    private func weatherPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.78), Color.blue.opacity(0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Inline snapshot preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
            }
            .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 8)
    }

    private func musicPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.68), Color.pink.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Media", systemImage: "play.square.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Lock screen panel preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
            }
            .shadow(color: Color.purple.opacity(0.24), radius: 12, x: 0, y: 9)
    }

    private func timerPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.orange.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay {
                VStack(spacing: 6) {
                    Text("Timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("00:05:00")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 8)
    }

    private func weatherDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isWeatherDragging {
                    isWeatherDragging = true
                    weatherStartOffset = weatherOffset
                }

                let proposed = weatherStartOffset - Double(value.translation.height)
                weatherOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isWeatherDragging = false
            }
    }

    private func musicDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isMusicDragging {
                    isMusicDragging = true
                    musicStartOffset = musicOffset
                }

                let proposed = musicStartOffset - Double(value.translation.height)
                musicOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isMusicDragging = false
            }
    }

    private func timerDragGesture(in screenRect: CGRect, baseY: CGFloat, panelSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTimerDragging {
                    isTimerDragging = true
                    timerStartOffset = timerOffset
                }

                let proposed = timerStartOffset - Double(value.translation.height)
                timerOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    panelHeight: panelSize.height,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isTimerDragging = false
            }
    }

    private func clampedOffset(
        _ proposed: Double,
        baseCenterY: CGFloat,
        panelHeight: CGFloat,
        screenRect: CGRect
    ) -> Double {
        let halfHeight = panelHeight / 2
        let minCenterY = screenRect.minY + halfHeight
        let maxCenterY = screenRect.maxY - halfHeight
        let proposedCenter = baseCenterY - CGFloat(proposed)
        let clampedCenter = min(max(proposedCenter, minCenterY), maxCenterY)
        let derivedOffset = Double(baseCenterY - clampedCenter)
        return min(max(derivedOffset, offsetRange.lowerBound), offsetRange.upperBound)
    }
}

private func copyLatestCrashReport() {
    let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
    let fileManager = FileManager.default

    do {
        let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
        let crashFiles = files.filter { $0.contains("DynamicIsland") && $0.hasSuffix(".crash") }

        guard let latestCrash = crashFiles.sorted(by: >).first else {
            let alert = NSAlert()
            alert.messageText = "No Crash Reports Found"
            alert.informativeText = "No crash reports found for DynamicIsland"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let crashPath = (crashReportsPath as NSString).appendingPathComponent(latestCrash)
        let crashContent = try String(contentsOfFile: crashPath, encoding: .utf8)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crashContent, forType: .string)

        let alert = NSAlert()
        alert.messageText = "Crash Report Copied"
        alert.informativeText = "Crash report '\(latestCrash)' has been copied to clipboard"
        alert.alertStyle = .informational
        alert.runModal()
    } catch {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = "Failed to read crash reports: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}

struct Shortcuts: View {
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableColorPickerFeature) var enableColorPickerFeature

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Text("Enable global keyboard shortcuts")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableShortcuts {
                Section {
                    KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Media")
                } footer: {
                    Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Toggle the Dynamic Island open or closed from anywhere.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Start Demo Timer:", name: .startDemoTimer)
                                .disabled(!enableShortcuts || !enableTimerFeature)
                            if !enableTimerFeature {
                                Text("Timer feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    Text("Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Clipboard History:", name: .clipboardHistoryPanel)
                                .disabled(!enableShortcuts || !enableClipboardManager)
                            if !enableClipboardManager {
                                Text("Clipboard feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Clipboard")
                } footer: {
                    Text("Opens the clipboard history panel. Default is Cmd+Shift+V (similar to Windows+V on PC). Only works when clipboard feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Screen Assistant:", name: .screenAssistantPanel)
                                .disabled(!enableShortcuts || !Defaults[.enableScreenAssistant])
                            if !Defaults[.enableScreenAssistant] {
                                Text("Screen Assistant feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("AI Assistant")
                } footer: {
                    Text("Opens the AI assistant panel for file analysis and conversation. Default is Cmd+Shift+A. Only works when screen assistant feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Toggle Terminal Tab:", name: .toggleTerminalTab)
                                .disabled(!enableShortcuts || !Defaults[.enableTerminalFeature])
                            if !Defaults[.enableTerminalFeature] {
                                Text("Terminal feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Opens the terminal tab in the notch. Default is Ctrl+`. Only works when terminal feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            KeyboardShortcuts.Recorder("Color Picker Panel:", name: .colorPickerPanel)
                                .disabled(!enableShortcuts || !enableColorPickerFeature)
                            if !enableColorPickerFeature {
                                Text("Color Picker feature is disabled")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                    }
                } header: {
                    Text("Color Picker")
                } footer: {
                    Text("Opens the color picker panel for screen color capture. Default is Cmd+Shift+P. Only works when color picker feature is enabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts are disabled")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Shortcuts")
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct TimerSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.mirrorSystemTimer) private var mirrorSystemTimer
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var showingResetConfirmation = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.timer.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            timerFeatureSection

            if enableTimerFeature {
                timerConfigurationSections
            }
        }
        .navigationTitle("Timer")
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        Section {
            Defaults.Toggle(key: .enableTimerFeature) {
                Text("Enable timer feature")
            }
            .settingsHighlight(id: highlightID("Enable timer feature"))

            if enableTimerFeature {
                Toggle("Enable timer live activity", isOn: $coordinator.timerLiveActivityEnabled)
                    .animation(.easeInOut, value: coordinator.timerLiveActivityEnabled)
                Defaults.Toggle(key: .mirrorSystemTimer) {
                    HStack(spacing: 8) {
                        Text("Mirror macOS Clock timers")
                        alphaBadge()
                    }
                }
                .help("Shows the system Clock timer in the notch when available. Requires Accessibility permission to read the status item.")
                .settingsHighlight(id: highlightID("Mirror macOS Clock timers"))

                Picker("Timer controls appear as", selection: $timerDisplayMode) {
                    ForEach(TimerDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help(timerDisplayMode.description)
                .settingsHighlight(id: highlightID("Timer controls appear as"))
            }
        } header: {
            Text("Timer Feature")
        } footer: {
            Text("Control timer availability, live activity behaviour, and whether the app mirrors timers started from the macOS Clock app.")
        }
    }

    @ViewBuilder
    private var timerConfigurationSections: some View {
        Group {
            lockScreenIntegrationSection
            customTimerSection
            appearanceSection
            timerPresetsSection
            timerSoundSection
        }
        .onAppear {
            if showsLabel {
                controlWindowEnabled = false
            }
        }
        .onChange(of: showsLabel) { _, show in
            if show {
                controlWindowEnabled = false
            }
        }
    }

    @ViewBuilder
    private var lockScreenIntegrationSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                Text("Show lock screen timer widget")
            }
            .settingsHighlight(id: highlightID("Show lock screen timer widget"))
            Picker("Timer surface", selection: timerSurfaceBinding) {
                ForEach(LockScreenTimerSurfaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!enableLockScreenTimerWidget)
            .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
            .settingsHighlight(id: highlightID("Timer surface"))

            if timerGlassModeIsGlass {
                Picker("Timer glass material", selection: $lockScreenTimerGlassStyle) {
                    ForEach(LockScreenGlassStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .disabled(!enableLockScreenTimerWidget)
                .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                .settingsHighlight(id: highlightID("Timer glass material"))

                if lockScreenTimerGlassStyle == .liquid {
                    Picker("Timer liquid mode", selection: $lockScreenTimerGlassCustomizationMode) {
                        ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!enableLockScreenTimerWidget)
                    .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
                    .settingsHighlight(id: highlightID("Timer liquid mode"))

                    if lockScreenTimerGlassCustomizationMode == .customLiquid {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Timer widget variant")
                                Spacer()
                                Text("v\(lockScreenTimerLiquidGlassVariant.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: timerVariantBinding, in: liquidVariantRange, step: 1)
                        }
                        .settingsHighlight(id: highlightID("Timer widget variant"))
                        .disabled(!enableLockScreenTimerWidget)
                        .opacity(enableLockScreenTimerWidget ? 1 : 0.4)
                    }
                } else {
                    Text("Uses the frosted blur treatment while glass mode is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Classic mode keeps the original translucent black background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(enableLockScreenTimerWidget ? 1 : 0.5)
            }
        } header: {
            Text("Lock Screen Integration")
        } footer: {
            Text("Mirrors the toggle found under Lock Screen settings so timer-specific workflows can enable or disable the widget without switching tabs.")
        }
    }

    @ViewBuilder
    private var customTimerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Custom Timer")
                    .font(.headline)

                TimerDurationStepperRow(title: String(localized: "Hours"), value: $customHours, range: 0...23)
                TimerDurationStepperRow(title: String(localized: "Minutes"), value: $customMinutes, range: 0...59)
                TimerDurationStepperRow(title: String(localized: "Seconds"), value: $customSeconds, range: 0...59)

                HStack {
                    Text("Current default:")
                        .foregroundStyle(.secondary)
                    Text(customDurationDisplay)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .padding(.vertical, 4)
            .onChange(of: customHours) { _, _ in updateCustomDuration() }
            .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
            .onChange(of: customSeconds) { _, _ in updateCustomDuration() }
        } header: {
            Text("Custom Timer")
        } footer: {
            Text("This duration powers the \"Custom\" option inside the timer popover for quick access.")
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Timer tint", selection: $colorMode) {
                ForEach(TimerIconColorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .settingsHighlight(id: highlightID("Timer tint"))

            if colorMode == .solid {
                ColorPicker("Solid colour", selection: $solidColor, supportsOpacity: false)
                    .settingsHighlight(id: highlightID("Solid colour"))
            }

            Toggle("Show timer name", isOn: $showsLabel)
            Toggle("Show countdown", isOn: $showsCountdown)
            Toggle("Show progress", isOn: $showsProgress)
            Toggle("Show preset list in timer tab", isOn: $showTimerPresetsInNotchTab)
                .settingsHighlight(id: highlightID("Show preset list in timer tab"))

            Toggle("Show floating pause/stop controls", isOn: $controlWindowEnabled)
                .disabled(showsLabel)
                .help("These controls sit beside the notch while a timer runs. They require the timer name to stay hidden for spacing.")

            Picker("Progress style", selection: $progressStyle) {
                ForEach(TimerProgressStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!showsProgress)
            .settingsHighlight(id: highlightID("Progress style"))
        } header: {
            Text("Appearance")
        } footer: {
            Text("Configure how the timer looks inside the closed notch. Progress can render as a ring around the icon or as horizontal bars.")
        }
    }

    @ViewBuilder
    private var timerPresetsSection: some View {
        Section {
            if timerPresets.isEmpty {
                Text("No presets configured. Add a preset to make it appear in the timer popover.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                TimerPresetListView(
                    presets: $timerPresets,
                    highlightProvider: highlightID,
                    moveUp: movePresetUp,
                    moveDown: movePresetDown,
                    remove: removePreset
                )
            }

            HStack {
                Button(action: addPreset) {
                    Label("Add Preset", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: { showingResetConfirmation = true }) {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Restore default timer presets?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                    Button("Restore", role: .destructive, action: resetPresets)
                }
            }
        } header: {
            Text("Timer Presets")
        } footer: {
            Text("Presets show up inside the timer popover with the configured name, duration, and accent colour. Reorder them to change the display order.")
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Timer Sound")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Button("Choose File", action: selectCustomTimerSound)
                        .buttonStyle(.bordered)
                }

                if let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath") {
                    Text("Custom: \(URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Default: dynamic.m4a")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Reset to Default") {
                    UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                }
                .buttonStyle(.bordered)
                .disabled(UserDefaults.standard.string(forKey: "customTimerSoundPath") == nil)
            }
        } header: {
            Text("Timer Sound")
        } footer: {
            Text("Select a custom sound to play when a timer ends. Supported formats include MP3, M4A, WAV, and AIFF.")
        }
    }

    private var customDurationDisplay: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = customTimerDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: customTimerDuration) ?? "0:00"
    }

    private func syncCustomDuration(_ value: Double? = nil) {
        let baseValue = value ?? customTimerDuration
        let components = TimerPreset.components(for: baseValue)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateCustomDuration() {
        let duration = TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        customTimerDuration = duration
    }

    private func addPreset() {
        let nextIndex = timerPresets.count + 1
        let defaultColor = Defaults[.accentColor]
        let newPreset = TimerPreset(name: "Preset \(nextIndex)", duration: 5 * 60, color: defaultColor)
        _ = withAnimation(.smooth) {
            timerPresets.append(newPreset)
        }
    }

    private func movePresetUp(_ index: Int) {
        guard index > timerPresets.startIndex else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index - 1)
        }
    }

    private func movePresetDown(_ index: Int) {
        guard index < timerPresets.index(before: timerPresets.endIndex) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index + 1)
        }
    }

    private func removePreset(_ index: Int) {
        guard timerPresets.indices.contains(index) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.remove(at: index)
        }
    }

    private func resetPresets() {
        _ = withAnimation(.smooth) {
            timerPresets = TimerPreset.defaultPresets
        }
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            if let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            }
        }
    }
}

private struct TimerDurationStepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
    }
}

private struct TimerPresetListView: View {
    @Binding var presets: [TimerPreset]
    let highlightProvider: (String) -> String
    let moveUp: (Int) -> Void
    let moveDown: (Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            presetRow(at: index)
        }
    }

    @ViewBuilder
    private func presetRow(at index: Int) -> some View {
        TimerPresetEditorRow(
            preset: $presets[index],
            isFirst: index == presets.startIndex,
            isLast: index == presets.index(before: presets.endIndex),
            highlightID: highlightID(for: index),
            moveUp: { moveUp(index) },
            moveDown: { moveDown(index) },
            remove: { remove(index) }
        )
    }

    private func highlightID(for index: Int) -> String? {
        index == presets.startIndex ? highlightProvider("Accent colour") : nil
    }
}

private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let highlightID: String?

    init(
        preset: Binding<TimerPreset>,
        isFirst: Bool,
        isLast: Bool,
        highlightID: String? = nil,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        _preset = preset
        self.isFirst = isFirst
        self.isLast = isLast
        self.highlightID = highlightID
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.remove = remove
    }

    private var components: TimerPreset.DurationComponents {
        TimerPreset.components(for: preset.duration)
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { components.hours },
            set: { updateDuration(hours: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { components.minutes },
            set: { updateDuration(minutes: $0) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { components.seconds },
            set: { updateDuration(seconds: $0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.updateColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(preset.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                TimerPresetComponentControl(title: String(localized: "Hours"), value: hoursBinding, range: 0...23)
                TimerPresetComponentControl(title: String(localized: "Minutes"), value: minutesBinding, range: 0...59)
                TimerPresetComponentControl(title: String(localized: "Seconds"), value: secondsBinding, range: 0...59)
            }

            ColorPicker("Accent colour", selection: colorBinding, supportsOpacity: false)
                .frame(maxWidth: 240, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(isFirst)

                Button(action: moveDown) {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(isLast)

                Spacer()

                Button(role: .destructive, action: remove) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 6)
        .settingsHighlightIfPresent(highlightID)
    }

    private func updateDuration(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var values = components
        if let hours { values.hours = hours }
        if let minutes { values.minutes = minutes }
        if let seconds { values.seconds = seconds }
        preset.duration = TimerPreset.duration(from: values)
    }
}

private struct TimerPresetComponentControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
        }
        .frame(width: 110, alignment: .leading)
    }
}

struct StatsSettings: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.statsStopWhenNotchCloses) var statsStopWhenNotchCloses
    @Default(.statsUpdateInterval) var statsUpdateInterval
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.cpuTemperatureUnit) var cpuTemperatureUnit

    private func highlightID(_ title: String) -> String {
        SettingsTab.stats.highlightID(for: title)
    }

    var enabledGraphsCount: Int {
        [showCpuGraph, showMemoryGraph, showGpuGraph, showNetworkGraph, showDiskGraph].filter { $0 }.count
    }

    private var formattedUpdateInterval: String {
        let seconds = Int(statsUpdateInterval.rounded())
        if seconds >= 60 {
            return "60 s (1 min)"
        } else if seconds == 1 {
            return "1 s"
        } else {
            return "\(seconds) s"
        }
    }

    private var shouldShowStatsBatteryWarning: Bool {
        !statsStopWhenNotchCloses && statsUpdateInterval <= 5
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableStatsFeature) {
                    Text("Enable system stats monitoring")
                }
                .settingsHighlight(id: highlightID("Enable system stats monitoring"))
                .onChange(of: enableStatsFeature) { _, newValue in
                    if !newValue {
                        statsManager.stopMonitoring()
                    }
                    // Note: Smart monitoring will handle starting when switching to stats tab
                }

            } header: {
                Text("General")
            } footer: {
                Text("When enabled, the Stats tab will display real-time system performance graphs. This feature requires system permissions and may use additional battery.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableStatsFeature {
                Section {
                    Defaults.Toggle(key: .statsStopWhenNotchCloses) {
                        Text("Stop monitoring after closing the notch")
                    }
                    .settingsHighlight(id: highlightID("Stop monitoring after closing the notch"))
                    .help("When enabled, stats monitoring stops a few seconds after the notch closes.")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Update interval")
                            Spacer()
                            Text(formattedUpdateInterval)
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $statsUpdateInterval, in: 1...60, step: 1)
                            .accessibilityLabel("Stats update interval")

                        Text("Controls how often system metrics refresh while monitoring is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if shouldShowStatsBatteryWarning {
                        Label {
                            Text("High-frequency updates without a timeout can increase battery usage.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                    }
                } header: {
                    Text("Monitoring Behavior")
                } footer: {
                    Text("Sampling can continue while the notch is closed when the timeout is disabled.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Defaults.Toggle(key: .showCpuGraph) {
                        Text("CPU Usage")
                    }
                    .settingsHighlight(id: highlightID("CPU Usage"))

                    if showCpuGraph {
                        Picker("Temperature unit", selection: $cpuTemperatureUnit) {
                            ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .settingsHighlight(id: highlightID("Temperature unit"))
                    }
                    Defaults.Toggle(key: .showMemoryGraph) {
                        Text("Memory Usage")
                    }
                    .settingsHighlight(id: highlightID("Memory Usage"))
                    Defaults.Toggle(key: .showGpuGraph) {
                        Text("GPU Usage")
                    }
                    .settingsHighlight(id: highlightID("GPU Usage"))
                    Defaults.Toggle(key: .showNetworkGraph) {
                        Text("Network Activity")
                    }
                    .settingsHighlight(id: highlightID("Network Activity"))
                    Defaults.Toggle(key: .showDiskGraph) {
                        Text("Disk I/O")
                    }
                    .settingsHighlight(id: highlightID("Disk I/O"))
                } header: {
                    Text("Graph Visibility")
                } footer: {
                    if enabledGraphsCount >= 4 {
                        Text("With \(enabledGraphsCount) graphs enabled, the Dynamic Island will expand horizontally to accommodate all graphs in a single row.")
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text("Each graph can be individually enabled or disabled. Network activity shows download/upload speeds, and disk I/O shows read/write speeds.")
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Text("Monitoring Status")
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statsManager.isMonitoring ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(statsManager.isMonitoring ? "Active" : "Stopped")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if statsManager.isMonitoring {
                        if showCpuGraph {
                            HStack {
                                Text("CPU Usage")
                                Spacer()
                                Text(statsManager.cpuUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showMemoryGraph {
                            HStack {
                                Text("Memory Usage")
                                Spacer()
                                Text(statsManager.memoryUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showGpuGraph {
                            HStack {
                                Text("GPU Usage")
                                Spacer()
                                Text(statsManager.gpuUsageString)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showNetworkGraph {
                            HStack {
                                Text("Network Download")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkDownload))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Network Upload")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.networkUpload))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if showDiskGraph {
                            HStack {
                                Text("Disk Read")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskRead))
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Disk Write")
                                Spacer()
                                Text(String(format: "%.1f MB/s", statsManager.diskWrite))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack {
                            Text("Last Updated")
                            Spacer()
                            Text(statsManager.lastUpdated, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Live Performance Data")
                }

                Section {
                    HStack {
                        Button(statsManager.isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                            if statsManager.isMonitoring {
                                statsManager.stopMonitoring()
                            } else {
                                statsManager.startMonitoring()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundColor(statsManager.isMonitoring ? .red : .blue)

                        Spacer()

                        Button("Clear Data") {
                            statsManager.clearHistory()
                        }
                        .buttonStyle(.bordered)
                        .disabled(statsManager.isMonitoring)
                    }
                } header: {
                    Text("Controls")
                }
            }
        }
        .navigationTitle("Stats")
    }
}

struct ClipboardSettings: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Default(.enableClipboardManager) var enableClipboardManager
    @Default(.clipboardHistorySize) var clipboardHistorySize
    @Default(.showClipboardIcon) var showClipboardIcon
    @Default(.clipboardDisplayMode) var clipboardDisplayMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.clipboard.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableClipboardManager) {
                    Text("Enable Clipboard Manager")
                }
                .settingsHighlight(id: highlightID("Enable Clipboard Manager"))
                .onChange(of: enableClipboardManager) { _, enabled in
                    if enabled {
                        clipboardManager.startMonitoring()
                    } else {
                        clipboardManager.stopMonitoring()
                    }
                }
            } header: {
                Text("Clipboard Manager")
            } footer: {
                Text("Monitor clipboard changes and keep a history of recent copies. Use Cmd+Shift+V to quickly access clipboard history.")
            }

            if enableClipboardManager {
                Section {
                    Defaults.Toggle(key: .showClipboardIcon) {
                        Text("Show Clipboard Icon")
                    }
                    .settingsHighlight(id: highlightID("Show Clipboard Icon"))

                    HStack {
                        Text("Display Mode")
                        Spacer()
                        Picker("", selection: $clipboardDisplayMode) {
                            ForEach(ClipboardDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    HStack {
                        Text("History Size")
                        Spacer()
                        Picker("", selection: $clipboardHistorySize) {
                            Text("3 items").tag(3)
                            Text("5 items").tag(5)
                            Text("7 items").tag(7)
                            Text("10 items").tag(10)
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("History Size"))

                    HStack {
                        Text("Current Items")
                        Spacer()
                        Text("\(clipboardManager.clipboardHistory.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Pinned Items")
                        Spacer()
                        Text("\(clipboardManager.pinnedItems.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Monitoring Status")
                        Spacer()
                        Text(clipboardManager.isMonitoring ? "Active" : "Stopped")
                            .foregroundColor(clipboardManager.isMonitoring ? .green : .secondary)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    switch clipboardDisplayMode {
                    case .popover:
                        Text("Popover mode shows clipboard as a dropdown attached to the clipboard button.")
                    case .panel:
                        Text("Panel mode shows clipboard in a floating window near the notch.")
                    case .separateTab:
                        Text("Separate Tab mode integrates Copied Items and Notes into a single view. If both are enabled, Notes appear on the right and Clipboard on the left.")
                    }
                }

                Section {
                    Button("Clear Clipboard History") {
                        clipboardManager.clearHistory()
                    }
                    .foregroundColor(.red)
                    .disabled(clipboardManager.clipboardHistory.isEmpty)

                    Button("Clear Pinned Items") {
                        clipboardManager.pinnedItems.removeAll()
                        clipboardManager.savePinnedItemsToDefaults()
                    }
                    .foregroundColor(.red)
                    .disabled(clipboardManager.pinnedItems.isEmpty)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Clear clipboard history removes recent copies. Clear pinned items removes your favorites. Both actions are permanent.")
                }

                if !clipboardManager.clipboardHistory.isEmpty {
                    Section {
                        ForEach(clipboardManager.clipboardHistory) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.type.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(item.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(timeAgoString(from: item.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(item.preview)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Current History")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clipboard")
        .onAppear {
            if enableClipboardManager && !clipboardManager.isMonitoring {
                clipboardManager.startMonitoring()
            }
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

struct ScreenAssistantSettings: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @Default(.enableScreenAssistant) var enableScreenAssistant
    @Default(.screenAssistantDisplayMode) var screenAssistantDisplayMode
    @Default(.geminiApiKey) var geminiApiKey
    @State private var apiKeyText = ""
    @State private var showingApiKey = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.screenAssistant.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenAssistant) {
                    Text("Enable Screen Assistant")
                }
                .settingsHighlight(id: highlightID("Enable Screen Assistant"))
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("AI-powered assistant that can analyze files, images, and provide conversational help. Use Cmd+Shift+A to quickly access the assistant.")
            }

            if enableScreenAssistant {
                Section {
                    HStack {
                        Text("Gemini API Key")
                        Spacer()
                        if geminiApiKey.isEmpty {
                            Text("Not Set")
                                .foregroundColor(.red)
                        } else {
                            Text("••••••••")
                                .foregroundColor(.green)
                        }

                        Button(showingApiKey ? "Hide" : (geminiApiKey.isEmpty ? "Set" : "Change")) {
                            if showingApiKey {
                                showingApiKey = false
                                if !apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Defaults[.geminiApiKey] = apiKeyText
                                }
                                apiKeyText = ""
                            } else {
                                showingApiKey = true
                                apiKeyText = geminiApiKey
                            }
                        }
                    }

                    if showingApiKey {
                        VStack(alignment: .leading, spacing: 8) {
                            SecureField("Enter your Gemini API Key", text: $apiKeyText)
                                .textFieldStyle(.roundedBorder)

                            Text("Get your free API key from Google AI Studio")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Button("Open Google AI Studio") {
                                    NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                                }
                                .buttonStyle(.link)

                                Spacer()

                                Button("Save") {
                                    Defaults[.geminiApiKey] = apiKeyText
                                    showingApiKey = false
                                    apiKeyText = ""
                                }
                                .disabled(apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    HStack {
                        Text("Display Mode")
                        Spacer()
                        Picker("", selection: $screenAssistantDisplayMode) {
                            ForEach(ScreenAssistantDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    HStack {
                        Text("Attached Files")
                        Spacer()
                        Text("\(screenAssistantManager.attachedFiles.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Recording Status")
                        Spacer()
                        Text(screenAssistantManager.isRecording ? "Recording" : "Ready")
                            .foregroundColor(screenAssistantManager.isRecording ? .red : .secondary)
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    switch screenAssistantDisplayMode {
                    case .popover:
                        Text("Popover mode shows the assistant as a dropdown attached to the AI button. Panel mode shows the assistant in a floating window near the notch.")
                    case .panel:
                        Text("Panel mode shows the assistant in a floating window near the notch. Popover mode shows the assistant as a dropdown attached to the AI button.")
                    }
                }

                Section {
                    Button("Clear All Files") {
                        screenAssistantManager.clearAllFiles()
                    }
                    .foregroundColor(.red)
                    .disabled(screenAssistantManager.attachedFiles.isEmpty)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Clear all files removes all attached files and audio recordings. This action is permanent.")
                }

                if !screenAssistantManager.attachedFiles.isEmpty {
                    Section {
                        ForEach(screenAssistantManager.attachedFiles) { file in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: file.type.iconName)
                                        .foregroundColor(.blue)
                                        .frame(width: 16)
                                    Text(file.type.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(timeAgoString(from: file.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(file.name)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Attached Files")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Screen Assistant")
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

struct ColorPickerSettings: View {
    @ObservedObject var colorPickerManager = ColorPickerManager.shared
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.showColorFormats) var showColorFormats
    @Default(.colorPickerDisplayMode) var colorPickerDisplayMode
    @Default(.colorHistorySize) var colorHistorySize
    @Default(.showColorPickerIcon) var showColorPickerIcon

    private func highlightID(_ title: String) -> String {
        SettingsTab.colorPicker.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableColorPickerFeature) {
                    Text("Enable Color Picker")
                }
                .settingsHighlight(id: highlightID("Enable Color Picker"))
            } header: {
                Text("Color Picker")
            } footer: {
                Text("Enable screen color picking functionality. Use Cmd+Shift+P to quickly access the color picker.")
            }

            if enableColorPickerFeature {
                Section {
                    Defaults.Toggle(key: .showColorPickerIcon) {
                        Text("Show Color Picker Icon")
                    }
                    .settingsHighlight(id: highlightID("Show Color Picker Icon"))

                    HStack {
                        Text("Display Mode")
                        Spacer()
                        Picker("", selection: $colorPickerDisplayMode) {
                            ForEach(ColorPickerDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("Display Mode"))

                    HStack {
                        Text("History Size")
                        Spacer()
                        Picker("", selection: $colorHistorySize) {
                            Text("5 colors").tag(5)
                            Text("10 colors").tag(10)
                            Text("15 colors").tag(15)
                            Text("20 colors").tag(20)
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 100)
                    }
                    .settingsHighlight(id: highlightID("History Size"))

                    Defaults.Toggle(key: .showColorFormats) {
                        Text("Show All Color Formats")
                    }
                    .settingsHighlight(id: highlightID("Show All Color Formats"))

                } header: {
                    Text("Settings")
                } footer: {
                    switch colorPickerDisplayMode {
                    case .popover:
                        Text("Popover mode shows color picker as a dropdown attached to the color picker button. Panel mode shows color picker in a floating window.")
                    case .panel:
                        Text("Panel mode shows color picker in a floating window. Popover mode shows color picker as a dropdown attached to the color picker button.")
                    }
                }

                Section {
                    HStack {
                        Text("Color History")
                        Spacer()
                        Text("\(colorPickerManager.colorHistory.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Picking Status")
                        Spacer()
                        Text(colorPickerManager.isPickingColor ? "Active" : "Ready")
                            .foregroundColor(colorPickerManager.isPickingColor ? .green : .secondary)
                    }

                    Button("Show Color Picker Panel") {
                        ColorPickerPanelManager.shared.showColorPickerPanel()
                    }
                    .disabled(!enableColorPickerFeature)

                } header: {
                    Text("Status & Actions")
                }

                Section {
                    Button("Clear Color History") {
                        colorPickerManager.clearHistory()
                    }
                    .foregroundColor(.red)
                    .disabled(colorPickerManager.colorHistory.isEmpty)

                    Button("Start Color Picking") {
                        colorPickerManager.startColorPicking()
                    }
                    .disabled(!enableColorPickerFeature || colorPickerManager.isPickingColor)

                } header: {
                    Text("Quick Actions")
                } footer: {
                    Text("Clear color history removes all picked colors. Start color picking begins screen color capture mode.")
                }
            }
        }
        .navigationTitle("Color Picker")
    }
}

struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.hasSeenOSDAlphaWarning) var hasSeenOSDAlphaWarning
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        Form {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission is needed to intercept system controls for the Custom OSD.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }

            if hasAccessibilityPermission || enableThirdPartyDDCIntegration {
                Section {
                    Toggle("Volume OSD", isOn: $enableOSDVolume)
                        .settingsHighlight(id: highlightID("Volume OSD"))
                    Toggle("Brightness OSD", isOn: $enableOSDBrightness)
                        .settingsHighlight(id: highlightID("Brightness OSD"))
                    Toggle("Keyboard Backlight OSD", isOn: $enableOSDKeyboardBacklight)
                        .settingsHighlight(id: highlightID("Keyboard Backlight OSD"))
                        .disabled(enableThirdPartyDDCIntegration)
                        .help(enableThirdPartyDDCIntegration ? "Disabled while external display integration is active \u{2014} brightness keys are handled by the external app." : "")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display custom OSD windows.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Picker("Material", selection: $osdMaterial) {
                        ForEach(availableOSDMaterials, id: \.self) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                    .onChange(of: osdMaterial) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }

                    if osdMaterial == .liquid {
                        if #available(macOS 26.0, *) {
                            Picker("Glass mode", selection: $osdLiquidGlassCustomizationMode) {
                                ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if osdLiquidGlassCustomizationMode == .customLiquid {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Custom liquid variant")
                                        Spacer()
                                        Text("v\(osdLiquidGlassVariant.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: osdLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                }
                            }
                        } else {
                            Text("Custom Liquid is available on macOS 26 or later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Icon & Progress Color", selection: $osdIconColorStyle) {
                        ForEach(OSDIconColorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Icon & Progress Color"))
                    .onChange(of: osdIconColorStyle) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Material Options:")
                        Text("• Frosted Glass: Translucent blur effect")
                        Text("• Liquid Glass: Modern glass effect (macOS 26+)")
                        Text("• Solid Dark/Light/Auto: Opaque backgrounds")
                        Text("")
                        Text("Color options control the icon and progress bar appearance. Auto adapts to system theme.")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("Live Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            CustomOSDView(
                                type: .constant(previewType),
                                value: .constant(previewValue),
                                icon: .constant("")
                            )
                            .frame(width: 200, height: 200)

                            HStack(spacing: 8) {
                                Button("Volume") {
                                    previewType = .volume
                                }
                                .buttonStyle(.bordered)

                                Button("Brightness") {
                                    previewType = .brightness
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Backlight") {
                                    previewType = .backlight
                                }
                                .buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                            
                            Slider(value: $previewValue, in: 0...1)
                                .frame(width: 160)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Custom OSD")
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                osdLiquidGlassCustomizationMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableCustomOSD = false
            }
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "Accessibility permission required",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "Request Access",
        openSettingsButtonTitle: String = "Open Settings",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(requestButtonTitle) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(openSettingsButtonTitle) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HUD()
}

struct NotesSettingsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.notes.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotes) {
                    Text("Enable Notes")
                }
                if Defaults[.enableNotes] {
                    Defaults.Toggle(key: .enableNotePinning) {
                        Text("Enable Note Pinning")
                    }
                    Defaults.Toggle(key: .enableNoteSearch) {
                        Text("Enable Note Search")
                    }
                    Defaults.Toggle(key: .enableNoteColorFiltering) {
                        Text("Enable Color Filtering")
                    }
                    Defaults.Toggle(key: .enableCreateFromClipboard) {
                        Text("Enable Create from Clipboard")
                    }
                    Defaults.Toggle(key: .enableNoteCharCount) {
                        Text("Show Character Count")
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Customize how you organize and create notes. Enabling color filtering and search helps manage large lists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notes")
    }
}

// MARK: - Terminal Settings

struct TerminalSettings: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @Default(.terminalShellPath) var terminalShellPath
    @Default(.terminalFontFamily) var terminalFontFamily
    @Default(.terminalFontSize) var terminalFontSize
    @Default(.terminalOpacity) var terminalOpacity
    @Default(.terminalMaxHeightFraction) var terminalMaxHeightFraction
    @Default(.terminalCursorStyle) var terminalCursorStyle
    @Default(.terminalScrollbackLines) var terminalScrollbackLines
    @Default(.terminalOptionAsMeta) var terminalOptionAsMeta
    @Default(.terminalMouseReporting) var terminalMouseReporting
    @Default(.terminalBoldAsBright) var terminalBoldAsBright
    @Default(.terminalBackgroundColor) var terminalBackgroundColor
    @Default(.terminalForegroundColor) var terminalForegroundColor
    @Default(.terminalCursorColor) var terminalCursorColor

    private func highlightID(_ title: String) -> String {
        SettingsTab.terminal.highlightID(for: title)
    }

    private var formattedMaxHeight: String {
        "\(Int(terminalMaxHeightFraction * 100))% of screen"
    }

    /// All monospaced font families available on the system.
    private var monospacedFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
                || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        .sorted()
    }

    /// Display name for the font picker — shows "System Monospaced" when no custom font is set.
    private var fontDisplayName: String {
        terminalFontFamily.isEmpty ? "System Monospaced" : terminalFontFamily
    }

    private var cursorStyleBinding: Binding<TerminalCursorStyleOption> {
        Binding(
            get: { TerminalCursorStyleOption(rawValue: terminalCursorStyle) ?? .blinkBlock },
            set: { terminalCursorStyle = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableTerminalFeature) {
                    Text("Enable terminal")
                }
                .settingsHighlight(id: highlightID("Enable terminal"))

                if enableTerminalFeature {
                    Defaults.Toggle(key: .terminalStickyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep terminal open until clicked outside")
                            Text("Prevents the terminal from closing when the cursor accidentally leaves the notch area.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Keep terminal open"))
                }
            } header: {
                Text("General")
            } footer: {
                Text("Adds a Guake-style dropdown terminal tab. The terminal session persists across notch open/close cycles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableTerminalFeature {
                // MARK: Shell
                Section {
                    HStack {
                        Text("Shell path")
                        Spacer()
                        TextField("", text: $terminalShellPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .multilineTextAlignment(.trailing)
                    }
                    .settingsHighlight(id: highlightID("Shell path"))
                } header: {
                    Text("Shell")
                }

                // MARK: Appearance
                Section {
                    Picker("Font family", selection: $terminalFontFamily) {
                        Text("System Monospaced").tag("")
                        Divider()
                        ForEach(monospacedFontFamilies, id: \.self) { family in
                            Text(family)
                                .font(.custom(family, size: 13))
                                .tag(family)
                        }
                    }
                    .onChange(of: terminalFontFamily) { _, newValue in
                        terminalManager.applyFontFamily(newValue)
                    }
                    .settingsHighlight(id: highlightID("Font family"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font size")
                            Spacer()
                            Text("\(Int(terminalFontSize)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $terminalFontSize, in: 8...24, step: 1)
                            .onChange(of: terminalFontSize) { _, newValue in
                                terminalManager.applyFontSize(newValue)
                            }
                    }
                    .settingsHighlight(id: highlightID("Font size"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Terminal opacity")
                            Spacer()
                            Text("\(Int(terminalOpacity * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $terminalOpacity, in: 0.3...1.0, step: 0.05)
                            .onChange(of: terminalOpacity) { _, newValue in
                                terminalManager.applyOpacity(newValue)
                            }
                    }
                    .settingsHighlight(id: highlightID("Terminal opacity"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Maximum height")
                            Spacer()
                            Text(formattedMaxHeight)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $terminalMaxHeightFraction, in: 0.2...0.5, step: 0.05)
                    }
                    .settingsHighlight(id: highlightID("Maximum height"))
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Terminal opacity only affects the terminal backdrop; text stays fully opaque. Blur uses the system material behind the window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Colors
                Section {
                    ColorPicker("Background", selection: $terminalBackgroundColor, supportsOpacity: false)
                        .onChange(of: terminalBackgroundColor) { _, newValue in
                            terminalManager.applyBackgroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Background color"))

                    ColorPicker("Foreground", selection: $terminalForegroundColor, supportsOpacity: false)
                        .onChange(of: terminalForegroundColor) { _, newValue in
                            terminalManager.applyForegroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Foreground color"))

                    ColorPicker("Cursor", selection: $terminalCursorColor, supportsOpacity: false)
                        .onChange(of: terminalCursorColor) { _, newValue in
                            terminalManager.applyCursorColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Cursor color"))

                    Toggle("Bold text as bright colors", isOn: $terminalBoldAsBright)
                        .onChange(of: terminalBoldAsBright) { _, newValue in
                            terminalManager.applyBoldAsBright(newValue)
                        }
                        .settingsHighlight(id: highlightID("Bold as bright"))
                } header: {
                    Text("Colors")
                } footer: {
                    Text("When bold-as-bright is off, bold text uses a heavier font weight instead of bright ANSI colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Cursor
                Section {
                    Picker("Cursor style", selection: cursorStyleBinding) {
                        ForEach(TerminalCursorStyleOption.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .onChange(of: terminalCursorStyle) { _, newValue in
                        if let style = TerminalCursorStyleOption(rawValue: newValue) {
                            terminalManager.applyCursorStyle(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Cursor style"))
                } header: {
                    Text("Cursor")
                }

                // MARK: Scrollback
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scrollback lines")
                            Spacer()
                            Text("\(terminalScrollbackLines)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(terminalScrollbackLines) },
                                set: { terminalScrollbackLines = Int($0) }
                            ),
                            in: 100...10000,
                            step: 100
                        )
                        .onChange(of: terminalScrollbackLines) { _, newValue in
                            terminalManager.applyScrollback(newValue)
                        }
                    }
                    .settingsHighlight(id: highlightID("Scrollback lines"))
                } header: {
                    Text("Scrollback")
                } footer: {
                    Text("Number of lines kept in the scrollback buffer. Higher values use more memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Input
                Section {
                    Toggle("Option as Meta key", isOn: $terminalOptionAsMeta)
                        .onChange(of: terminalOptionAsMeta) { _, newValue in
                            terminalManager.applyOptionAsMeta(newValue)
                        }
                        .settingsHighlight(id: highlightID("Option as Meta"))

                    Toggle("Allow mouse reporting", isOn: $terminalMouseReporting)
                        .onChange(of: terminalMouseReporting) { _, newValue in
                            terminalManager.applyMouseReporting(newValue)
                        }
                        .settingsHighlight(id: highlightID("Mouse reporting"))
                } header: {
                    Text("Input")
                } footer: {
                    Text("Option as Meta sends Esc+key instead of macOS special characters. Mouse reporting forwards mouse events to terminal applications like vim or tmux.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Actions
                Section {
                    Button("Restart Shell") {
                        terminalManager.restartShell()
                    }
                    .disabled(!terminalManager.isProcessRunning)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Restarts the shell process. Any unsaved work in the terminal will be lost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Terminal")
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // resize to keep memory low.
                let thumb = NSImage(size: NSSize(width: 32, height: 32))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private extension QuickShareProvider {
    var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}
