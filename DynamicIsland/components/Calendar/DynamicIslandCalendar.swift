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
import EventKit

// MARK: - Shared auto-scroll helpers

/// Partition events into all-day and timed groups.
func partitionEvents(_ events: [EventModel]) -> (allDay: [EventModel], timed: [EventModel]) {
    (events.filter { $0.isAllDay }, events.filter { !$0.isAllDay })
}

/// Determine which timed event to scroll to, based on a reference time.
/// For today, pass Date() to find in-progress/upcoming events.
/// For other dates, pass startOfDay to scroll to the first event of that day.
func scrollTargetForTimedEvents(timed: [EventModel], referenceTime: Date) -> EventModel? {
    // Prefer an event that carries a conference (Join Meeting) link and is
    // currently active, so its Join button is scrolled into view (#566 feedback:
    // all-day events used to push these out of the visible area).
    let activeConference = timed.first(where: { event in
        guard event.conferenceURL != nil else { return false }
        if event.type.isReminder {
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let inProgress = timed.first(where: { event in
        if event.type.isReminder {
            // Reminders are point-in-time; treat as "in progress" only within 1h of start
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let nextUpcoming = timed.first(where: { $0.start > referenceTime })
    let lastTimed = timed.last
    return activeConference ?? inProgress ?? nextUpcoming ?? lastTimed
}

/// Reference time for auto-scroll: current time for today, startOfDay for past/future days.
func scrollReferenceTime(for date: Date) -> Date {
    Calendar.current.isDateInToday(date) ? Date() : Calendar.current.startOfDay(for: date)
}

// MARK: - Compact all-day events strip

/// Shared layout metrics for the all-day events strip.
///
/// The strip height and the space reserved for it in the timed-events list must
/// stay in sync across `AllDayEventsStrip`, `StandaloneEventCardList`, and
/// `EventListView`. Centralising the values here avoids the hardcoded
/// `28` / `3` / `41` / `30` duplicated in multiple views (#566 review).
private enum AllDayStripMetrics {
    /// Height of the horizontal chip row inside `AllDayEventsStrip`.
    static let chipRowHeight: CGFloat = 28
    /// Vertical padding applied around the chips and the strip content.
    static let verticalPadding: CGFloat = 3
    /// Top inset pushed onto the timed `List` so `scrollTo(.top)` lands the
    /// target event fully below the floating all-day overlay
    /// (chip row + 1pt divider + 1pt margin ≈ 30pt). Shared by `EventListView`
    /// and `StandaloneEventCardList` so both reserve exactly the same space.
    /// (#566 review: de-duplicate the hardcoded 28/3/41/30)
    static let listTopInset: CGFloat = 30
}

/// Horizontal, single-row strip of all-day events.
///
/// The Dynamic Island calendar panel is height-constrained (`CalendarView` is
/// capped at a fixed height). The previous design stacked one full row per
/// all-day event in a pinned top section, so two all-day events could consume
/// the entire panel and leave no room for the timed-events scroll area below
/// (#566 follow-up). This strip keeps the all-day section at a constant
/// single-row height regardless of how many all-day events exist — extra
/// events scroll horizontally within the strip instead of growing vertically.
private struct AllDayEventsStrip: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]
    var onToggleReminder: ((String, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        allDayChip(event)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, AllDayStripMetrics.verticalPadding)
            }
            .frame(height: AllDayStripMetrics.chipRowHeight)
            .clipped()

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func allDayChip(_ event: EventModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(event.calendar.color))
                .frame(width: 8, height: 8)

            Text(event.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)

            if event.isAllDay {
                Text("All-day")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(1)
            }

            if event.type.isReminder, let onToggleReminder {
                reminderToggle(for: event, using: onToggleReminder)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, AllDayStripMetrics.verticalPadding)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture {
            if let url = event.calendarAppURL() {
                openURL(url)
            }
        }
    }

    private func reminderToggle(for event: EventModel, using onToggleReminder: @escaping (String, Bool) -> Void) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }
        return ReminderToggle(
            isOn: Binding(
                get: { isCompleted },
                set: { newValue in onToggleReminder(event.id, newValue) }
            ),
            color: Color(event.calendar.color)
        )
    }
}

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2
}

/// Reports the measured width of a single date cell, used to translate a
/// mouse drag (in points) into a scroll-position step.
private struct CellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WheelPicker: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    /// Tracks a mouse press-drag so an external mouse can scrub dates like a
    /// trackpad two-finger scroll (macOS ScrollView doesn't pan on mouse drag).
    @State private var dragAnchorPos: Int? = nil
    @State private var measuredCellWidth: CGFloat = 40
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum
                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation {
                                scrollPosition = index
                            }
                            if Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
        .onPreferenceChange(CellWidthKey.self) { measuredCellWidth = $0 }
        // Mouse press-drag scrubs dates (trackpad two-finger scroll still works
        // natively — that arrives as a scroll event, not a drag gesture, so the
        // two never conflict). Steps = drag points / measured cell width.
        // `.simultaneousGesture` (not `.gesture`) so the drag runs alongside the
        // strip's own gestures instead of swallowing the date-cell taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragAnchorPos == nil { dragAnchorPos = scrollPosition }
                    guard let start = dragAnchorPos, measuredCellWidth > 1 else { return }
                    let steps = Int((-value.translation.width / measuredCellWidth).rounded())
                    let spacerNum = config.offset
                    let totalItems = totalDateItems() + 2 * spacerNum
                    let newPos = min(max(spacerNum, start + steps), totalItems - 1)
                    if newPos != scrollPosition {
                        withTransaction(Transaction(animation: nil)) {
                            scrollPosition = newPos
                        }
                    }
                }
                .onEnded { _ in
                    dragAnchorPos = nil
                }
        )
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                dateCircle(date: date, isToday: isToday, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.effectiveAccentBackground : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .id(id)
        .background(GeometryReader { geo in
            Color.clear.preference(key: CellWidthKey.self, value: geo.size.width)
        })
    }

    private func dayText(date: String, isToday: Bool, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .white : Color(white: 0.65))
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.effectiveAccent : .clear)
                .frame(width: 20, height: 20)
            Text(date.date)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.65))
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        guard let newIndex = newValue else { return }
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
        let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    private func indexForDate(_ date: Date) -> Int {
        let spacerNum = config.offset
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        return spacerNum + stepIndex
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = index - spacerNum
        return cal.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var dateExpanded = false
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    var body: some View {
        VStack(spacing: 0) {
            // Compact-by-default date header: when collapsed it shows a single
            // small "weekday, month day" line (~20pt) so the event list below
            // keeps almost the entire 120pt panel. Hovering the header expands
            // the horizontal date-scroll strip (with edge-fade shadows) — the
            // shadows therefore appear exactly when it is scrollable, matching
            // the maintainer's review #1 intent (not permanently drawn).
            HStack(alignment: .center, spacing: 8) {
                // Left label: one compact line when collapsed; month + year when expanded.
                VStack(alignment: .leading, spacing: 1) {
                    if dateExpanded {
                        Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(selectedDate.formatted(.dateTime.year()))
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundColor(Color(white: 0.65))
                    } else {
                        Text(selectedDate.formatted(.dateTime.weekday(.abbreviated))
                             + ", " + selectedDate.formatted(.dateTime.month(.abbreviated))
                             + " " + selectedDate.formatted(.dateTime.day()))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 72, alignment: .leading)

                ZStack {
                    WheelPicker(selectedDate: $selectedDate, config: Config())
                        .frame(maxWidth: .infinity)
                    // Edge fades indicating the date strip is horizontally
                    // scrollable. Subtle (0.45) so they hint without hiding text.
                    LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Use the WheelPicker's natural height (50pt) when expanded so its
                // date cells are never clipped top/bottom. Collapsed = 0 height.
                .frame(height: dateExpanded ? 50 : 0)
                .opacity(dateExpanded ? 1 : 0)
                .allowsHitTesting(dateExpanded)
                .clipped()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.18)) {
                    dateExpanded = inside
                }
            }

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events,
                hideCompletedReminders: hideCompletedReminders,
                hideAllDayEvents: hideAllDayEvents
            )
            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                Spacer(minLength: 0)
            } else {
                EventListView(events: calendarManager.events, selectedDate: selectedDate)
            }
        }
        .listRowBackground(Color.clear)
        // Restore the original expanded-notch window height (120pt). Bumping this
        // to 158 grew the whole Dynamic Island window and distorted the music
        // player's internal spacing — both flagged in review #2. The internal
        // wins (all-day floating strip + single-line title) remain, so more timed
        // events are visible at 120 than before, but we no longer enlarge the
        // window or touch the music player's layout.
        .frame(height: 120)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }
}

struct StandaloneCalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()
    @State private var datePickerScrollTarget: Date?
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return symbols }

        let firstWeekdayIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        var ordered = Array(symbols[firstWeekdayIndex...])
        ordered.append(contentsOf: symbols[..<firstWeekdayIndex])
        return ordered
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide))
    }

    private var yearTitle: String {
        displayedMonth.formatted(.dateTime.year())
    }

    private var monthDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else { return [] }

        var days: [Date] = []
        var current = firstWeekInterval.start
        while current < lastWeekInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    private var resolvedNotchHeight: CGFloat {
        let height = vm.notchSize.height
        return height > 0 ? height : openNotchSize.height
    }

    private var headerHeight: CGFloat {
        max(24, vm.effectiveClosedNotchHeight)
    }

    private var maxTabContentHeight: CGFloat {
        let available = resolvedNotchHeight - headerHeight - 36
        return max(130, available)
    }

    var body: some View {
        GeometryReader { geometry in
            let paneSpacing: CGFloat = 12
            let paneWidth = max((geometry.size.width - paneSpacing) / 2, 0)
            let paneHeight = max(0, geometry.size.height)

            HStack(alignment: .top, spacing: paneSpacing) {
                leftPickerPane
                    .frame(width: paneWidth, alignment: .topLeading)
                    .frame(height: paneHeight, alignment: .topLeading)
                    .layoutPriority(1)

                rightEventsPane
                    .frame(width: paneWidth, alignment: .topLeading)
                    .frame(height: paneHeight, alignment: .topLeading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        }
        .frame(height: maxTabContentHeight)
        .clipped()
        .onAppear {
            selectedDate = Date.now
            displayedMonth = selectedDate.startOfMonth
            requestDatePickerCenterOnCurrentDate()
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            withAnimation(.smooth(duration: 0.22)) {
                displayedMonth = newDate.startOfMonth
            }
            Task {
                await calendarManager.updateCurrentDate(newDate)
            }
        }
        .onChange(of: vm.notchState) { _, newState in
            guard newState == .open else { return }
            selectedDate = Date.now
            displayedMonth = selectedDate.startOfMonth
            requestDatePickerCenterOnCurrentDate()
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
    }

    private var leftPickerPane: some View {
        GeometryReader { geometry in
            let pickerViewportHeight = max(96, geometry.size.height - 56)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(monthTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Text(yearTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(white: 0.65))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button(action: showPreviousMonth) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)

                        Button(action: showNextMonth) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.white)
                }

                ScrollViewReader { proxy in
                    VStack(spacing: 6) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7), spacing: 6) {
                            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                                Text(symbol.prefix(1))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color(white: 0.55))
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        ZStack {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7), spacing: 6) {
                                    ForEach(monthDays, id: \.self) { day in
                                        dayCell(for: day)
                                            .id(calendar.startOfDay(for: day))
                                    }
                                }
                                .padding(.bottom, 2)
                            }
                            .onChange(of: datePickerScrollTarget) { _, target in
                                guard let target else { return }
                                centerDatePicker(on: target, proxy: proxy)
                            }

                            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                                .frame(maxHeight: .infinity, alignment: .top)

                            LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 16)
                                .allowsHitTesting(false)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: max(0, pickerViewportHeight - 22))
                        .clipped()
                    }
                    .frame(height: pickerViewportHeight)
                }
                .frame(height: pickerViewportHeight)
                .clipped()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .clipped()
    }

    private var rightEventsPane: some View {
        Group {
            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StandaloneEventCardList(
                    events: filteredEvents,
                    selectedDate: selectedDate,
                    showFullEventTitles: Defaults[.showFullEventTitles],
                    onToggleReminder: { reminderID, completed in
                        Task {
                            await calendarManager.setReminderCompleted(reminderID: reminderID, completed: completed)
                        }
                    }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func dayCell(for day: Date) -> some View {
        let isCurrentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                selectedDate = day
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.effectiveAccent)
                        .frame(width: 28, height: 28)
                }

                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(dayTextColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return Color(white: 0.35) }
        if isToday { return Color.effectiveAccent }
        return .white
    }

    private func showPreviousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = newMonth.startOfMonth
            selectedDate = newMonth.startOfMonth
        }
    }

    private func showNextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = newMonth.startOfMonth
            selectedDate = newMonth.startOfMonth
        }
    }

    private func requestDatePickerCenterOnCurrentDate() {
        datePickerScrollTarget = calendar.startOfDay(for: selectedDate)
    }

    private func centerDatePicker(on target: Date, proxy: ScrollViewProxy) {
        let normalizedTarget = calendar.startOfDay(for: target)
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(normalizedTarget, anchor: .center)
            }
            if datePickerScrollTarget == normalizedTarget {
                datePickerScrollTarget = nil
            }
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

private extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
}

private struct StandaloneEventCardList: View {
    @Environment(\.openURL) private var openURL
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    let events: [EventModel]
    let selectedDate: Date
    let showFullEventTitles: Bool
    let onToggleReminder: (String, Bool) -> Void
    @State private var initialAutoScrollDone = false

    private var allDayEvents: [EventModel] {
        partitionEvents(events).allDay.sorted { $0.start < $1.start }
    }

    private var timedEvents: [EventModel] {
        // Sorted by start time so `scrollTargetForTimedEvents` (which uses
        // `first(where:)` to pick in-progress / next-upcoming) returns the true
        // nearest-to-now event, and the list renders chronologically. (#566)
        partitionEvents(events).timed.sorted { $0.start < $1.start }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let refTime = scrollReferenceTime(for: selectedDate)
        guard let target = scrollTargetForTimedEvents(timed: timedEvents, referenceTime: refTime) else { return }

        // The List reserves `listTopInset` at its top when an all-day strip is
        // present, so scrolling to `.top` lands the target event just below the
        // overlay — fully visible. Mirrors `EventListView`. (#566)
        let anchor: UnitPoint = .top
        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: anchor)
            }
        }
    }

    var body: some View {
        // Timed-events list fills the whole panel; the all-day strip floats as
        // an overlay on top (zero vertical cost) so the scroll area below keeps
        // its full height inside the constrained calendar panel. The List
        // carries a top padding equal to the strip height so scrollTo(.top)
        // lands the target event fully below the overlay. Using `List` (instead
        // of the previous `LazyVStack`-in-`ScrollView`) keeps the scroll
        // behaviour and look consistent with `EventListView` and gives built-in
        // separators. (#566 review: unify the two event lists)
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(timedEvents) { event in
                            eventCard(event)
                                .id(event.id)
                                .padding(.bottom, 8)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    // Push list content down so scrollTo(.top) positions the
                    // target event fully below the floating all-day overlay.
                    .padding(.top, allDayEvents.isEmpty ? 0 : AllDayStripMetrics.listTopInset)
                }
                .onAppear {
                    scrollToRelevantEvent(proxy: proxy)
                    if !timedEvents.isEmpty {
                        initialAutoScrollDone = true
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    scrollToRelevantEvent(proxy: proxy)
                }
                .onChange(of: timedEvents.isEmpty) { wasEmpty, isEmpty in
                    // Retrigger the initial auto-scroll once, when timed events become
                    // available after the view appeared (e.g. async calendar load).
                    // Guarded so later data refreshes don't re-scroll. (#566 follow-up)
                    guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                    scrollToRelevantEvent(proxy: proxy)
                    initialAutoScrollDone = true
                }
            }

            // Floating all-day strip overlay (28pt chip row + 1pt divider ≈ 29pt).
            // It sits above the list and events scroll underneath it, like macOS
            // Calendar's Day view. Matches `EventListView`'s overlay exactly so
            // the reserved `listTopInset` (30) lines up with the real strip
            // height. No shadow gradient is drawn on top of the events anymore.
            if !allDayEvents.isEmpty {
                AllDayEventsStrip(
                    events: allDayEvents,
                    onToggleReminder: onToggleReminder
                )
                .background(Color.black.opacity(0.95))
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func eventCard(_ event: EventModel) -> some View {
        if event.type.isReminder {
            Button {
                if let url = event.calendarAppURL() {
                    openURL(url)
                }
            } label: {
                reminderCard(event)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        } else {
            calendarEventCard(event)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = event.calendarAppURL() {
                        openURL(url)
                    }
                }
                .padding(.horizontal, 2)
        }
    }

    private func reminderCard(_ event: EventModel) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }

        return HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { isCompleted },
                    set: { newValue in onToggleReminder(event.id, newValue) }
                ),
                color: Color(event.calendar.color)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(showFullEventTitles ? nil : 2)

                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                }
            }

            Spacer(minLength: 8)

            if !event.isAllDay {
                Text(event.start, style: .time)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.75))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(isCompleted ? 0.55 : 1)
    }

    private func calendarEventCard(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(event.calendar.color))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(showFullEventTitles ? nil : 2)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }

                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                } else {
                    Text(event.start, style: .time)
                        .font(.caption)
                        .foregroundColor(.white)
                    Text(event.end, style: .time)
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.65))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1)
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    let selectedDate: Date
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @State private var initialAutoScrollDone = false

    static func filteredEvents(
        events: [EventModel],
        hideCompletedReminders: Bool,
        hideAllDayEvents: Bool
    ) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !hideCompletedReminders
                }
            }
            if event.isAllDay && hideAllDayEvents {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(
            events: events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    private var allDayEvents: [EventModel] {
        partitionEvents(filteredEvents).allDay.sorted { $0.start < $1.start }
    }

    private var timedEvents: [EventModel] {
        // Sorted by start time so `scrollTargetForTimedEvents` (which uses
        // `first(where:)` to pick in-progress / next-upcoming) returns the true
        // nearest-to-now event, and the list renders chronologically. (#566)
        partitionEvents(filteredEvents).timed.sorted { $0.start < $1.start }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let refTime = scrollReferenceTime(for: selectedDate)
        guard let target = scrollTargetForTimedEvents(timed: timedEvents, referenceTime: refTime) else { return }

        // The List has .padding(.top: 30) when all-day events are present,
        // which lives inside the ScrollView's coordinate space.  Scrolling to
        // .top therefore places the target event just below that inset — i.e.
        // fully visible beneath the floating all-day overlay.
        let anchor: UnitPoint = .top
        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: anchor)
            }
        }
    }

    var body: some View {
        // Timed-events list fills the whole panel; the all-day strip floats as
        // an overlay on top (zero vertical cost) so the scroll area below keeps
        // its full height inside the 120pt Dynamic Island panel.  The List
        // carries a top padding equal to the strip height so that
        // scrollTo(.top) lands the target event fully below the overlay. (#566)
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(timedEvents) { event in
                            Button(action: {
                                if let url = event.calendarAppURL() {
                                    openURL(url)
                                }
                            }) {
                                eventRow(event)
                            }
                            .id(event.id)
                            .padding(.leading, -5)
                            .buttonStyle(PlainButtonStyle())
                            .listRowSeparator(.automatic)
                            .listRowSeparatorTint(.gray.opacity(0.2))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    // Push list content down so scrollTo(.top) positions the
                    // target event fully below the floating all-day overlay
                    // (28pt strip + 1pt separator + 1pt margin = 30pt).
                    .padding(.top, allDayEvents.isEmpty ? 0 : AllDayStripMetrics.listTopInset)

                    // (Shadows intentionally removed — #566 feedback: the gradient
                    // overlay was permanently drawn on top of the events.)
                }
                .onAppear {
                    scrollToRelevantEvent(proxy: proxy)
                    if !timedEvents.isEmpty {
                        initialAutoScrollDone = true
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    scrollToRelevantEvent(proxy: proxy)
                }
                .onChange(of: timedEvents.isEmpty) { wasEmpty, isEmpty in
                    // Retrigger the initial auto-scroll once, when timed events become
                    // available after the view appeared (e.g. async calendar load).
                    // Guarded so later data refreshes don't re-scroll. (#566 follow-up)
                    guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                    scrollToRelevantEvent(proxy: proxy)
                    initialAutoScrollDone = true
                }
            }

            if !allDayEvents.isEmpty {
                AllDayEventsStrip(
                    events: allDayEvents,
                    onToggleReminder: { reminderID, completed in
                        Task {
                            await calendarManager.setReminderCompleted(
                                reminderID: reminderID, completed: completed
                            )
                        }
                    }
                )
                .background(Color.black.opacity(0.95))
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                        
                        // Show Join button if conference URL is available
                        if let conferenceURL = event.conferenceURL {
                            ConferenceJoinButton(url: conferenceURL, event: event)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Conference Provider

enum ConferenceProvider: CaseIterable {
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord, generic
    
    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .generic: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: return Color(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: return Color(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .gotomeeting: return Color(red: 0.95, green: 0.5, blue: 0.13)
        case .bluejeans: return Color(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: return Color(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: return Color(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: return Color(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: return Color.accentColor
        }
    }
    
    private var hostIdentifiers: [String] {
        switch self {
        case .zoom: return ["zoom.us"]
        case .teams: return ["teams.microsoft.com"]
        case .meet: return ["meet.google.com"]
        case .webex: return ["webex.com"]
        case .facetime: return ["facetime.apple.com"]
        case .gotomeeting: return ["gotomeeting.com"]
        case .bluejeans: return ["bluejeans.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si", "jitsi"]
        case .discord: return ["discord.gg", "discord.com"]
        case .generic: return []
        }
    }
    
    var nativeURLScheme: String? {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .facetime: return "facetime"
        case .discord: return "discord"
        default: return nil
        }
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        return allCases.first { provider in
            provider.hostIdentifiers.contains { host.contains($0) }
        } ?? .generic
    }
}

// MARK: - Conference Join Button

struct ConferenceJoinButton: View {
    let url: URL
    let event: EventModel
    @Environment(\.openURL) private var openURL
    
    private var provider: ConferenceProvider { .detect(from: url) }
    private var isJoinable: Bool {
        event.start.addingTimeInterval(-15 * 60) <= Date()
    }
    
    private var buttonText: String {
        event.eventStatus == .inProgress ? "Rejoin" : "Join"
    }
    
    var body: some View {
        Button(action: {
            if let scheme = provider.nativeURLScheme,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = scheme
                if let nativeURL = components.url {
                    openURL(nativeURL)
                    return
                }
            }
            openURL(url)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.name.isEmpty ? buttonText : "\(buttonText) \(provider.name)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isJoinable ? .white : Color(white: 0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isJoinable ? provider.color.opacity(0.85) : Color.gray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isJoinable)
        .help(isJoinable ? "Join the meeting" : "Meeting starts at \(event.start.formatted(date: .omitted, time: .shortened))")
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(DynamicIslandViewModel.init())
}
