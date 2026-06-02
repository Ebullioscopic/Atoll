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
import AppKit
import CoreGraphics


struct LockScreenWeatherWidget: View {
	let snapshot: LockScreenWeatherSnapshot
	@ObservedObject private var focusManager = DoNotDisturbManager.shared
	@ObservedObject private var calendarManager = CalendarManager.shared
	@Default(.enableDoNotDisturbDetection) private var focusDetectionEnabled
	@Default(.showDoNotDisturbIndicator) private var focusIndicatorEnabled
	@Default(.enableLockScreenFocusWidget) private var lockScreenFocusWidgetEnabled
	@Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
	@Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
	@Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
	@Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
	@Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
	@Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
	@Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
	@Default(.lockScreenWeatherWidgetRowOrder) private var lockScreenWeatherWidgetRowOrder
	@Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
	@Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
	@Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
	@Default(.lockScreenReminderChipStyle) private var lockScreenReminderChipStyle
	@Default(.reminderSneakPeekDuration) private var reminderSneakPeekDuration

	@State private var currentTime = Date()
	@State private var calendarRowVisible: Bool = false
	@State private var lastCalendarLine: String = ""
	@State private var calendarRowRenderToken: Int = 0
	@State private var widgetWidthRemeasureToken: Int = 0
	@State private var lastBadgeLogKey: String = ""
	private var currentCalendarEventID: String {
		nextCalendarEvent?.id ?? "no_event"
	}

	private let inlinePrimaryFont = Font.system(size: 22, weight: .semibold, design: .rounded)
	private let inlineSecondaryFont = Font.system(size: 13, weight: .medium, design: .rounded)
	private let secondaryLabelColor = Color.white.opacity(0.7)
	private static let sunriseFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		formatter.locale = .current
		return formatter
	}()

	// MARK: - Refresh
	/// Refreshes every 15 seconds (general refresh), and optionally also ticks exactly on minute boundaries
	/// *only when the screen is locked* and the calendar widget is enabled.
	private final class LockAwareTicker: ObservableObject {
		@Published var now: Date = Date()

		private var refreshTimer: Timer?
		private var minuteTimer: Timer?

		private var lockObserver: NSObjectProtocol?
		private var unlockObserver: NSObjectProtocol?

		private var isLocked: Bool = false
		private var minuteAlignedEnabled: Bool = false

		func start() {
			stop()
			installLockObservers()
			refreshLockStateFromSystem()
			startGeneralRefresh()
			fireNow()
			updateMinuteAlignedTimer()
		}

		func stop() {
			refreshTimer?.invalidate()
			refreshTimer = nil

			minuteTimer?.invalidate()
			minuteTimer = nil

			if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
			if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
			lockObserver = nil
			unlockObserver = nil
		}

		func fireNow() {
			now = Date()
		}

		/// Enable/disable the minute-aligned ticker (minute boundary ticks).
		/// It will only actually run when the screen is locked.
		func setMinuteAlignedEnabled(_ enabled: Bool) {
			minuteAlignedEnabled = enabled
			updateMinuteAlignedTimer()
		}

		private func startGeneralRefresh() {
			refreshTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
				self?.fireNow()
			}
			refreshTimer?.tolerance = 0
			if let refreshTimer {
				RunLoop.main.add(refreshTimer, forMode: .common)
			}
		}

		private func refreshLockStateFromSystem() {
			if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
				if let locked = dict["CGSSessionScreenIsLocked"] as? Bool {
					isLocked = locked
				}
			}
		}

		private func installLockObservers() {
			lockObserver = DistributedNotificationCenter.default().addObserver(
				forName: NSNotification.Name("com.apple.screenIsLocked"),
				object: nil,
				queue: .main
			) { [weak self] _ in
				guard let self else { return }
				self.isLocked = true
				self.fireNow()
				self.updateMinuteAlignedTimer()
			}

			unlockObserver = DistributedNotificationCenter.default().addObserver(
				forName: NSNotification.Name("com.apple.screenIsUnlocked"),
				object: nil,
				queue: .main
			) { [weak self] _ in
				guard let self else { return }
				self.isLocked = false
				self.fireNow()
				self.updateMinuteAlignedTimer()
			}
		}

		private func updateMinuteAlignedTimer() {
			let shouldRun = isLocked && minuteAlignedEnabled
			if !shouldRun {
				minuteTimer?.invalidate()
				minuteTimer = nil
				return
			}

			if minuteTimer != nil {
				return
			}

			scheduleNextBoundaryAndRepeat()
		}

		private func scheduleNextBoundaryAndRepeat() {
			let current = Date()
			let calendar = Calendar.current

			var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: current)
			components.second = 0
			let thisMinute = calendar.date(from: components) ?? current
			let nextMinute = calendar.date(byAdding: .minute, value: 1, to: thisMinute) ?? current.addingTimeInterval(60)

			let initialDelay = max(0.0, nextMinute.timeIntervalSince(current))
			minuteTimer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
				guard let self else { return }
				self.fireNow()

				self.minuteTimer?.invalidate()
				self.minuteTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
					self?.fireNow()
				}
				self.minuteTimer?.tolerance = 0
				if let minuteTimer {
					RunLoop.main.add(minuteTimer, forMode: .common)
				}
			}
			minuteTimer?.tolerance = 0
			if let minuteTimer {
				RunLoop.main.add(minuteTimer, forMode: .common)
			}
		}

		deinit {
			stop()
		}
	}

	@StateObject private var minuteTicker = LockAwareTicker()

	private enum CalendarLookaheadWindow: String {
		case mins15 = "15m"
		case mins30 = "30m"
		case hour1 = "1h"
		case hours3 = "3h"
		case hours6 = "6h"
		case hours12 = "12h"
		case restOfDay = "rest_of_day"
		case allTime = "all_time"

		var minutes: Int? {
			switch self {
			case .mins15: return 15
			case .mins30: return 30
			case .hour1: return 60
			case .hours3: return 180
			case .hours6: return 360
			case .hours12: return 720
			case .restOfDay, .allTime: return nil
			}
		}
	}

	private enum CalendarAfterStartWindow: String {
		case min1 = "1m"
		case mins5 = "5m"
		case mins10 = "10m"
		case mins15 = "15m"
		case mins30 = "30m"
		case mins45 = "45m"
		case hour1 = "1h"
		case hours2 = "2h"

		var minutes: Int {
			switch self {
			case .min1: return 1
			case .mins5: return 5
			case .mins10: return 10
			case .mins15: return 15
			case .mins30: return 30
			case .mins45: return 45
			case .hour1: return 60
			case .hours2: return 120
			}
		}
	}

	private var selectedLookaheadWindow: CalendarLookaheadWindow {
		let raw = lockScreenCalendarEventLookaheadWindow
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		switch raw {
		case "all time", "all_time", "alltime":
			return .allTime
		case "rest of the day", "rest_of_day", "restofday":
			return .restOfDay
		case "15m", "15 mins", "15min", "15mins":
			return .mins15
		case "30m", "30 mins", "30min", "30mins":
			return .mins30
		case "1h", "1 hour", "1hour":
			return .hour1
		case "3h", "3 hours", "3hours":
			return .hours3
		case "6h", "6 hours", "6hours":
			return .hours6
		case "12h", "12 hours", "12hours":
			return .hours12
		default:
			return CalendarLookaheadWindow(rawValue: lockScreenCalendarEventLookaheadWindow) ?? .hours3
		}
	}

	private var selectedAfterStartWindow: CalendarAfterStartWindow {
		let raw = lockScreenShowCalendarEventAfterStartWindow
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		switch raw {
		case "1m", "1 min", "1 minute", "1min":
			return .min1
		case "5m", "5 min", "5 mins", "5 minutes", "5min":
			return .mins5
		case "10m", "10 min", "10 mins", "10 minutes", "10min":
			return .mins10
		case "15m", "15 min", "15 mins", "15 minutes", "15min":
			return .mins15
		case "30m", "30 min", "30 mins", "30 minutes", "30min":
			return .mins30
		case "45m", "45 min", "45 mins", "45 minutes", "45min":
			return .mins45
		case "1h", "1 hr", "1 hour", "1hour":
			return .hour1
		case "2h", "2 hrs", "2 hours", "2hours", "2hour":
			return .hours2
		default:
			return CalendarAfterStartWindow(rawValue: lockScreenShowCalendarEventAfterStartWindow) ?? .mins5
		}
	}

	private func lookaheadEndDate(from now: Date) -> Date? {
		switch selectedLookaheadWindow {
		case .allTime:
			return nil
		case .restOfDay:
			let calendar = Calendar.current
			let startOfToday = calendar.startOfDay(for: now)
			return calendar.date(byAdding: .day, value: 1, to: startOfToday)
		default:
			if let minutes = selectedLookaheadWindow.minutes {
				return Calendar.current.date(byAdding: .minute, value: minutes, to: now)
			}
			return nil
		}
	}

	private func isEventEligibleForLookahead(_ event: EventModel, now: Date) -> Bool {
		if event.isAllDay {
			return false
		}
		if lockScreenShowCalendarEventEntireDuration, event.start <= now, event.end >= now {
			return true
		}
		guard event.start > now else { return false }
		guard let endDate = lookaheadEndDate(from: now) else {
			return true
		}
		return event.start <= endDate
	}

	private var lockScreenAllowedCalendarIDs: Set<String>? {
		guard lockScreenCalendarSelectionMode != "all" else { return nil }
		return lockScreenSelectedCalendarIDs
	}

	private func passesLockScreenCalendarFilter(_ event: EventModel) -> Bool {
		guard let allowed = lockScreenAllowedCalendarIDs else { return true }
		guard !allowed.isEmpty else { return false }
		return allowed.contains(event.calendar.id)
	}

	private var nextCalendarEvent: EventModel? {
		let now = currentTime

		if lockScreenShowCalendarEventEntireDuration {
			let candidates = calendarManager.lockScreenEvents
				.filter { $0.end >= now }
				.filter(passesLockScreenCalendarFilter)
				.filter { isEventEligibleForLookahead($0, now: now) }
				.sorted { $0.start < $1.start }
			return candidates.first
		}

		let graceMinutes = lockScreenShowCalendarEventAfterStartEnabled
			? selectedAfterStartWindow.minutes
			: 0

		if graceMinutes > 0 {
			let graceEndForEvent: (EventModel) -> Date = { event in
				Calendar.current.date(byAdding: .minute, value: graceMinutes, to: event.start) ?? event.start
			}

			let activeCandidates = calendarManager.lockScreenEvents
				.filter { !$0.isAllDay }
				.filter(passesLockScreenCalendarFilter)
				.filter { $0.start <= now && $0.end >= now }
				.filter { now <= graceEndForEvent($0) }
				.sorted { $0.start < $1.start }

			if let active = activeCandidates.first {
				return active
			}
		}

		let upcoming = calendarManager.lockScreenEvents
			.filter { $0.start > now }
			.filter(passesLockScreenCalendarFilter)
			.filter { isEventEligibleForLookahead($0, now: now) }
			.sorted { $0.start < $1.start }

		return upcoming.first
	}

	private var shouldShowCalendarRow: Bool {
		lockScreenShowCalendarEvent && nextCalendarEvent != nil
	}

	private var shouldShowFocusInCalendarSlot: Bool {
		shouldShowFocusWidget && !shouldShowCalendarRow
	}

	private var shouldCombineFocusAndCalendar: Bool {
		shouldShowFocusWidget && shouldShowCalendarRow
	}

	private enum RowKind {
		case weather
		case focus
		case calendar
	}

	private var orderedRowKinds: [RowKind] {
		switch lockScreenWeatherWidgetRowOrder {
		case "weather_focus_calendar":
			return [.weather, .focus, .calendar]
		case "weather_calendar_focus":
			return [.weather, .calendar, .focus]
		case "focus_weather_calendar":
			return [.focus, .weather, .calendar]
		case "focus_calendar_weather":
			return [.focus, .calendar, .weather]
		case "calendar_weather_focus":
			return [.calendar, .weather, .focus]
		case "calendar_focus_weather":
			return [.calendar, .focus, .weather]
		default:
			return [.weather, .calendar, .focus]
		}
	}

	private var enabledRowKinds: [RowKind] {
		var enabled: Set<RowKind> = [.weather]
		if lockScreenShowCalendarEvent { enabled.insert(.calendar) }
		if shouldShowFocusWidget { enabled.insert(.focus) }
		if shouldShowFocusInCalendarSlot { enabled.insert(.calendar); enabled.remove(.focus) }
		if shouldCombineFocusAndCalendar { enabled.remove(.focus) }
		return orderedRowKinds.filter { enabled.contains($0) }
	}

	private var fullRowOrder: [RowKind] {
		orderedRowKinds
	}

	private func isRowActive(_ kind: RowKind) -> Bool {
		switch kind {
		case .weather:
			return true
		case .focus:
			return shouldShowFocusWidget
		case .calendar:
			return nextCalendarEvent != nil
		}
	}

	private var shouldCollapseGap: Bool {
		fullRowOrder.count == 3
	}

	private var collapseDistance: CGFloat {
		26 + focusWidgetSpacing
	}

	private var collapseOffsetForBottomRow: CGFloat {
		guard shouldCollapseGap else { return 0 }
		let middleKind = fullRowOrder[1]
		let bottomKind = fullRowOrder[2]

		let middleActive = isRowActive(middleKind)
		let bottomActive = isRowActive(bottomKind)

		return (!middleActive && bottomActive) ? -collapseDistance : 0
	}

	private var isInline: Bool { snapshot.widgetStyle == .inline }
	private var stackAlignment: VerticalAlignment { isInline ? .firstTextBaseline : .top }
	private var stackSpacing: CGFloat { isInline ? 14 : 22 }
	private var mainRowAlignment: Alignment {
		if isInline {
			return shouldCombineFocusAndCalendar ? .center : .leading
		}
		return .center
	}
	private var secondaryRowAlignment: Alignment { .center }
	private var focusRowAlignment: Alignment { .center }
	private var gaugeDiameter: CGFloat { 64 }
	private var topPadding: CGFloat { isInline ? 6 : 22 }
	private var bottomPadding: CGFloat { isInline ? 6 : 10 }

	private var monochromeGaugeTint: Color {
		Color.white.opacity(0.9)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: focusWidgetSpacing) {
			ForEach(Array(enabledRowKinds.enumerated()), id: \.offset) { index, kind in
				rowView(for: kind)
					.offset(y: offsetForRow(index: index))
					.animation(.easeInOut(duration: 0.3), value: collapseOffsetForBottomRow)
			}
		}
		.id(widgetWidthRemeasureToken)
		.frame(maxWidth: .infinity, alignment: .leading)
		.foregroundStyle(Color.white.opacity(0.65))
		.padding(.horizontal, 10)
		.padding(.top, topPadding)
		.padding(.bottom, bottomPadding)
		.background(Color.clear)
		.shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
		.onReceive(minuteTicker.$now) { currentTime = $0 }
		.onAppear {
			minuteTicker.start()
			minuteTicker.setMinuteAlignedEnabled(lockScreenShowCalendarEvent)
			currentTime = Date()
			calendarRowVisible = shouldShowCalendarRow

			Task {
				await calendarManager.checkCalendarAuthorization()
				await calendarManager.checkReminderAuthorization()
				await calendarManager.updateLockScreenEvents(force: true)
			}

			if let event = nextCalendarEvent {
				lastCalendarLine = eventLineText(for: event)
				logBadgeColor(event: event, reason: "on-appear")
			}
		}
		.onChange(of: lockScreenShowCalendarEvent) { _, enabled in
			minuteTicker.setMinuteAlignedEnabled(enabled)
		}
		.onChange(of: lockScreenCalendarEventLookaheadWindow) { _, _ in
			Task { await calendarManager.updateLockScreenEvents(force: true) }
		}
		.onChange(of: lockScreenCalendarSelectionMode) { _, _ in
			Task { await calendarManager.updateLockScreenEvents(force: true) }
		}
		.onChange(of: lockScreenSelectedCalendarIDs) { _, _ in
			Task { await calendarManager.updateLockScreenEvents(force: true) }
		}
		.onDisappear { minuteTicker.stop() }
		.onChange(of: currentCalendarEventID) { _, _ in
			calendarRowRenderToken &+= 1
			if nextCalendarEvent != nil {
				widgetWidthRemeasureToken &+= 1
			}

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
				calendarRowRenderToken &+= 1
				if nextCalendarEvent != nil {
					widgetWidthRemeasureToken &+= 1
				}
			}
		}
		.onChange(of: currentCalendarEventID) { _, _ in
			if let event = nextCalendarEvent {
				let newLine = eventLineText(for: event)
				if !newLine.isEmpty {
					lastCalendarLine = newLine
				}
				logBadgeColor(event: event, reason: "event-change")
			}
		}
		.onChange(of: lockScreenReminderChipStyle) { _, _ in
			if let event = nextCalendarEvent {
				logBadgeColor(event: event, reason: "chip-style-change")
			}
		}
		.onChange(of: shouldShowCalendarRow) { _, newValue in
			withAnimation(.easeInOut(duration: 0.25)) {
				calendarRowVisible = newValue
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityLabel)
	}

	private func offsetForRow(index: Int) -> CGFloat {
		if enabledRowKinds.count != 3 { return 0 }
		if index == 2 {
			return collapseOffsetForBottomRow
		}
		return 0
	}

	@ViewBuilder
	private func rowView(for kind: RowKind) -> some View {
		switch kind {
		case .weather:
			mainWidgetRow
		case .calendar:
			if shouldCombineFocusAndCalendar {
				combinedFocusCalendarRow
			} else if shouldShowFocusInCalendarSlot {
				focusRowInCalendarSlot
			} else {
				nextEventRow
			}
		case .focus:
			if shouldCombineFocusAndCalendar {
				EmptyView()
			} else {
				focusWidget
					.opacity(shouldShowFocusWidget ? 1 : 0)
					.accessibilityHidden(!shouldShowFocusWidget)
					.allowsHitTesting(false)
			}
		}
	}

	private var focusRowInCalendarSlot: some View {
		HStack(alignment: .center, spacing: 8) {
			focusIcon
				.font(.system(size: 20, weight: .semibold))
				.frame(width: 26, height: 26)

			Text(focusDisplayName)
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
				.allowsTightening(true)
		}
		.frame(maxWidth: .infinity, alignment: secondaryRowAlignment)
		.padding(.horizontal, 2)
		.opacity(shouldShowFocusWidget ? 1 : 0)
		.accessibilityLabel("Focus active: \(focusDisplayName)")
		.allowsHitTesting(false)
	}

	private var mainWidgetRow: some View {
		HStack(alignment: stackAlignment, spacing: stackSpacing) {
			if let charging = snapshot.charging {
				chargingSegment(for: charging)
			}

			if let battery = snapshot.battery {
				batterySegment(for: battery)
			}

			if let bluetooth = snapshot.bluetooth {
				bluetoothSegment(for: bluetooth)
			}

			if let airQuality = snapshot.airQuality {
				airQualitySegment(for: airQuality)
			}

			weatherSegment

			if snapshot.showsSunrise, let sunriseText = sunriseTimeText {
				sunriseSegment(text: sunriseText)
			}

			if shouldShowLocation {
				locationSegment
			}
		}
		.frame(maxWidth: .infinity, alignment: mainRowAlignment)
	}

	private var nextEventRow: some View {
		let event = nextCalendarEvent
		let line = shouldShowCalendarRow ? eventLineText(for: event) : lastCalendarLine
		let iconConfig = calendarRowIconConfig(for: event)

		return LockScreenCalendarEventRow(
			line: line,
			isVisible: calendarRowVisible,
			renderToken: calendarRowRenderToken,
			font: inlinePrimaryFont,
			alignment: secondaryRowAlignment,
			iconName: iconConfig.name,
			iconRenderingMode: iconConfig.renderingMode,
			iconColors: iconConfig.colors
		)
	}

	private var combinedFocusCalendarRow: some View {
		let event = nextCalendarEvent
		let line = shouldShowCalendarRow ? eventLineText(for: event) : lastCalendarLine
		let iconConfig = calendarRowIconConfig(for: event)

		return HStack(alignment: .center, spacing: 10) {
			HStack(alignment: .center, spacing: 6) {
				calendarIconView(iconConfig)
					.frame(width: 26, height: 26)

				Text(line)
					.font(inlinePrimaryFont)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
					.allowsTightening(true)
			}
			.layoutPriority(2)

			Text("•")
				.font(inlinePrimaryFont)
				.foregroundStyle(secondaryLabelColor)
				.accessibilityHidden(true)

			HStack(alignment: .center, spacing: 8) {
				focusIcon
					.font(.system(size: 20, weight: .semibold))
					.frame(width: 26, height: 26)

				Text(focusDisplayName)
					.font(inlinePrimaryFont)
					.lineLimit(1)
					.minimumScaleFactor(0.85)
					.allowsTightening(true)
			}
			.layoutPriority(1)
		}
		.frame(maxWidth: .infinity, alignment: .center)
		.padding(.horizontal, 2)
		.id(calendarRowRenderToken)
		.opacity(shouldShowFocusWidget && shouldShowCalendarRow ? 1 : 0)
		.accessibilityLabel("\(line). Focus active: \(focusDisplayName)")
		.allowsHitTesting(false)
	}

	@ViewBuilder
	private func calendarIconView(_ iconConfig: (name: String, renderingMode: SymbolRenderingMode, colors: [Color])) -> some View {
		let image = Image(systemName: iconConfig.name)
			.font(.system(size: 20, weight: .semibold))

		let isPalette = String(describing: iconConfig.renderingMode)
			.lowercased()
			.contains("palette")

		if isPalette, iconConfig.colors.count >= 2 {
			image
				.symbolRenderingMode(.palette)
				.foregroundStyle(iconConfig.colors[0], iconConfig.colors[1])
		} else if iconConfig.colors.count >= 2 {
			image
				.symbolRenderingMode(iconConfig.renderingMode)
				.foregroundStyle(iconConfig.colors[0], iconConfig.colors[1])
		} else if iconConfig.colors.count == 1 {
			image
				.symbolRenderingMode(iconConfig.renderingMode)
				.foregroundStyle(iconConfig.colors[0])
		} else {
			image
				.symbolRenderingMode(iconConfig.renderingMode)
		}
	}

	private func calendarRowIconConfig(for event: EventModel?) -> (name: String, renderingMode: SymbolRenderingMode, colors: [Color]) {
		guard let event else {
			return (name: "calendar.badge", renderingMode: .hierarchical, colors: [Color.white.opacity(0.9)])
		}

		let badgeColor = reminderChipColor(for: event)
		logBadgeColor(event: event, reason: "icon-config")

		if event.type.isReminder || event.calendar.isReminder {
			if isReminderCritical(event) {
				return (name: "exclamationmark.triangle.fill", renderingMode: .multicolor, colors: [])
			}
			return (
				name: "calendar.badge",
				renderingMode: .palette,
				colors: [badgeColor, Color.white.opacity(0.6)]
			)
		}

		let eventBadgeColor = eventAccentColor(for: event)
		return (
			name: "calendar.badge",
			renderingMode: .palette,
			colors: [eventBadgeColor, Color.white.opacity(0.6)]
		)
	}

	private func logBadgeColor(event: EventModel, reason: String) {
		let key = "\(event.id)|\(lockScreenReminderChipStyle.rawValue)|\(isReminderCritical(event))|\(reason)"
		lastBadgeLogKey = key

		let color = reminderChipColor(for: event)
		let nsColor = NSColor(color).usingColorSpace(.deviceRGB)
		if let nsColor {
			var red: CGFloat = 0
			var green: CGFloat = 0
			var blue: CGFloat = 0
			var alpha: CGFloat = 0
			nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
			let hex = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
			let alphaText = String(format: "%.2f", alpha)
			NSLog("LockScreenCalendarRow badge color: %@ alpha=%@ style=%@ critical=%@ reason=%@", hex, alphaText, lockScreenReminderChipStyle.rawValue, String(isReminderCritical(event)), reason)
		} else {
			NSLog("LockScreenCalendarRow badge color: <unavailable> style=%@ critical=%@ reason=%@", lockScreenReminderChipStyle.rawValue, String(isReminderCritical(event)), reason)
		}
	}

	private func reminderChipColor(for event: EventModel) -> Color {
		if isReminderCritical(event) { return .red }
		switch lockScreenReminderChipStyle {
		case .monochrome:
			return Color.white.opacity(0.85)
		case .eventColor:
			let color = reminderAccentColor(for: event)
			return color.ensureMinimumBrightness(factor: 0.7)
		}
	}

	private func reminderAccentColor(for event: EventModel) -> Color {
		Color(event.calendar.color)
	}

	private func eventAccentColor(for event: EventModel) -> Color {
		Color(event.calendar.color).ensureMinimumBrightness(factor: 0.7)
	}

	private func isReminderCritical(_ event: EventModel) -> Bool {
		guard event.type.isReminder || event.calendar.isReminder else { return false }
		let window = TimeInterval(reminderSneakPeekDuration)
		guard window > 0 else { return false }
		let remaining = event.start.timeIntervalSince(currentTime)
		return remaining > 0 && remaining <= window
	}

	private func eventLineText(for event: EventModel?) -> String {
		guard let event else { return "" }
		let now = currentTime

		if event.isAllDay {
            return "\(String(format: String(localized: "All-day"))) • \(event.title)"
        }

		let timeString = event.start.formatted(date: .omitted, time: .shortened)

		if event.start <= now && event.end >= now {
			let leading = lockScreenShowCalendarStartTimeAfterBegins ? "\(timeString) • " : ""
			let suffix: String
			if lockScreenShowCalendarTimeRemaining {
				let secondsLeft = event.end.timeIntervalSince(now)
				let minutesLeft = max(0, Int(ceil(secondsLeft / 60.0)))
                suffix = " • \(String(format: String(localized: "%@ left"), countdownText(fromMinutes: minutesLeft)))"
            } else {
				suffix = ""
			}
			return "\(leading)\(event.title)\(suffix)"
		}

		guard lockScreenShowCalendarCountdown else {
			return "\(timeString) • \(event.title)"
		}

		let secondsUntilStart = event.start.timeIntervalSince(now)
		let totalMinutes = max(0, Int(ceil(secondsUntilStart / 60.0)))
        return "\(timeString) • \(event.title) • \(String(format: String(localized: "in %@"), (countdownText(fromMinutes: totalMinutes))))"
	}

	private func countdownText(fromMinutes minutes: Int) -> String {
		if minutes < 60 {
			return "\(minutes)m"
		}

        let hours = String(format: String(localized: "%lldh"), minutes / 60)
		let mins = minutes % 60
        let minStr = String(format: String(localized: "%lldm"), minutes % 60)
		if mins == 0 {
			return "\(hours)"
		}
		return "\(hours) \(minStr)"
	}

	private var sunriseTimeText: String? {
		guard let sunrise = snapshot.sunCycle?.sunrise else { return nil }
		return Self.sunriseFormatter.string(from: sunrise)
	}

	@ViewBuilder
	private var weatherSegment: some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineWeatherSegment
		case .circular:
			circularWeatherSegment
		}
	}

	private var inlineWeatherSegment: some View {
		HStack(alignment: .center, spacing: 6) {
			Image(systemName: snapshot.symbolName)
				.font(.system(size: 26, weight: .medium))
				.symbolRenderingMode(.hierarchical)
			Text(snapshot.temperatureText)
				.font(inlinePrimaryFont)
				.kerning(-0.3)
				.lineLimit(1)
				.minimumScaleFactor(0.9)
				.layoutPriority(2)
		}
	}

	@ViewBuilder
	private var circularWeatherSegment: some View {
		if let info = snapshot.temperatureInfo {
			temperatureGauge(for: info)
		} else {
			inlineWeatherSegment
		}
	}

	@ViewBuilder
	private func chargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineChargingSegment(for: info)
		case .circular:
			circularChargingSegment(for: info)
		}
	}

	@ViewBuilder
	private func batterySegment(for info: LockScreenWeatherSnapshot.BatteryInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
            inlineBatterySegment(for: info)
		case .circular:
			circularBatterySegment(for: info)
		}
	}

	private func inlineChargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			if let iconName = chargingIconName(for: info) {
				Image(systemName: iconName)
					.font(.system(size: 20, weight: .semibold))
					.symbolRenderingMode(.hierarchical)
			}
			Text(inlineChargingLabel(for: info))
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func circularChargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		if let rawLevel = info.batteryLevel {
			let level = clampedBatteryLevel(rawLevel)

			VStack(spacing: 6) {
				Gauge(value: Double(level), in: 0...100) {
					EmptyView()
				} currentValueLabel: {
					chargingGlyph(for: info)
				} minimumValueLabel: {
					Text("0")
						.font(.system(size: 11, weight: .medium, design: .rounded))
						.foregroundStyle(secondaryLabelColor)
				} maximumValueLabel: {
					Text("100")
						.font(.system(size: 11, weight: .medium, design: .rounded))
						.foregroundStyle(secondaryLabelColor)
				}
				.gaugeStyle(.accessoryCircularCapacity)
				.tint(batteryTint(for: level))
				.frame(width: gaugeDiameter, height: gaugeDiameter)

				Text(chargingDetailLabel(for: info))
					.font(inlineSecondaryFont)
					.foregroundStyle(secondaryLabelColor)
					.lineLimit(1)
			}
			.layoutPriority(1)
		} else {
			inlineChargingSegment(for: info)
		}
	}

	private func circularBatterySegment(for info: LockScreenWeatherSnapshot.BatteryInfo) -> some View {
		let level = clampedBatteryLevel(info.batteryLevel)
		let symbolName = info.usesLaptopSymbol ? "laptopcomputer" : batteryIconName(for: level)

		return VStack(spacing: 6) {
			Gauge(value: Double(level), in: 0...100) {
				EmptyView()
			} currentValueLabel: {
				Image(systemName: symbolName)
					.font(.system(size: 20, weight: .semibold))
					.foregroundStyle(Color.white)
			} minimumValueLabel: {
				EmptyView()
			} maximumValueLabel: {
				EmptyView()
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.tint(batteryTint(for: level))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text("\(level)%")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func bluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineBluetoothSegment(for: info)
		case .circular:
			circularBluetoothSegment(for: info)
		}
	}

	private func inlineBluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Image(systemName: info.iconName)
				.font(.system(size: 20, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
			Text(bluetoothPercentageText(for: info.batteryLevel))
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}
    
    private func inlineBatterySegment(for info: LockScreenWeatherSnapshot.BatteryInfo) -> some View {
        let level = clampedBatteryLevel(info.batteryLevel)

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Optional icon (laptop vs battery glyph)
            Image(systemName: info.usesLaptopSymbol ? "laptopcomputer" : batteryIconName(for: level))
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            // ✅ The actual percentage text you want in inline style
            Text("\(level)%")
                .font(inlinePrimaryFont)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .layoutPriority(1)
    }

	private func circularBluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
		let clamped = clampedBatteryLevel(info.batteryLevel)

		return VStack(spacing: 6) {
			Gauge(value: Double(clamped), in: 0...100) {
				EmptyView()
			} currentValueLabel: {
				Image(systemName: info.iconName)
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(Color.white)
			} minimumValueLabel: {
				EmptyView()
			} maximumValueLabel: {
				EmptyView()
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.tint(bluetoothTint(for: clamped))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text(bluetoothPercentageText(for: info.batteryLevel))
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		.layoutPriority(1)
	}

	@ViewBuilder
	private func airQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		switch snapshot.widgetStyle {
		case .inline:
			inlineAirQualitySegment(for: info)
		case .circular:
			circularAirQualitySegment(for: info)
		}
	}

	private func inlineAirQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Image(systemName: "wind")
				.font(.system(size: 18, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
			inlineComposite(primary: "\(info.scale.compactLabel) \(info.index)", secondary: info.category.displayName)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(1)
	}

	private func circularAirQualitySegment(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> some View {
		let range = info.scale.gaugeRange
		let clampedValue = min(max(Double(info.index), range.lowerBound), range.upperBound)

		return VStack(spacing: 6) {
			Gauge(value: clampedValue, in: range) {
				EmptyView()
			} currentValueLabel: {
				Text("\(info.index)")
					.font(.system(size: 20, weight: .semibold, design: .rounded))
					.foregroundStyle(Color.white)
			}
			.gaugeStyle(.accessoryCircular)
			.tint(aqiTint(for: info))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			Text("\(info.scale.compactLabel) · \(info.category.displayName)")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
				.lineLimit(1)
		}
		.layoutPriority(1)
	}

	private func temperatureGauge(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> some View {
		let range = temperatureRange(for: info)

		return VStack(spacing: 6) {
			Gauge(value: info.current, in: range) {
				EmptyView()
			} currentValueLabel: {
				temperatureCenterLabel(for: info)
			}
			.gaugeStyle(.accessoryCircular)
			.tint(temperatureTint(for: info))
			.frame(width: gaugeDiameter, height: gaugeDiameter)

			HStack {
				Text(minimumTemperatureLabel(for: info))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(secondaryLabelColor)
				Spacer()
				Text(maximumTemperatureLabel(for: info))
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(secondaryLabelColor)
			}
			.frame(width: gaugeDiameter)
		}
		.layoutPriority(1)
	}

	private var locationSegment: some View {
		Text(snapshot.locationName ?? "")
			.font(isInline ? inlinePrimaryFont : inlineSecondaryFont)
			.lineLimit(1)
			.truncationMode(.tail)
			.minimumScaleFactor(0.75)
			.layoutPriority(0.7)
	}

	private func sunriseSegment(text: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 4) {
			Image(systemName: "sunrise.fill")
				.font(.system(size: 20, weight: .semibold))
				.symbolRenderingMode(.hierarchical)
			Text(text)
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.layoutPriority(0.8)
		.accessibilityLabel("Sunrise at \(text)")
	}

	private var shouldShowLocation: Bool {
		snapshot.showsLocation && (snapshot.locationName?.isEmpty == false)
	}

	private var focusWidgetSpacing: CGFloat {
		guard lockScreenShowCalendarEvent || lockScreenFocusWidgetEnabled else { return 0 }
		return isInline ? 14 : 20
	}

	private var shouldShowFocusWidget: Bool {
		lockScreenFocusWidgetEnabled &&
		focusDetectionEnabled &&
		focusIndicatorEnabled &&
		focusManager.isDoNotDisturbActive &&
		!focusDisplayName.isEmpty
	}

	private var focusDisplayName: String {
		let trimmed = focusManager.currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmed.isEmpty {
			return trimmed
		}
		if focusMode == .doNotDisturb {
			return "Do Not Disturb"
		}
		let fallback = focusMode.displayName
		return fallback.isEmpty ? "Focus" : fallback
	}

	private var focusMode: FocusModeType {
		FocusModeType.resolve(
			identifier: focusManager.currentFocusModeIdentifier,
			name: focusManager.currentFocusModeName
		)
	}

	private var focusIcon: Image {
		focusMode
			.resolvedActiveIcon(usePrivateSymbol: true)
			.renderingMode(.template)
	}

	private var focusWidget: some View {
		HStack(alignment: .center, spacing: 8) {
			focusIcon
				.font(.system(size: 20, weight: .semibold))
				.frame(width: 26, height: 26)

			Text(focusDisplayName)
				.font(inlinePrimaryFont)
				.lineLimit(1)
				.minimumScaleFactor(0.85)
		}
		.frame(maxWidth: .infinity, alignment: focusRowAlignment)
		.padding(.horizontal, 2)
		.accessibilityLabel("Focus active: \(focusDisplayName)")
	}

	private func chargingIconName(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
		let icon = info.iconName
		return icon.isEmpty ? nil : icon
	}

	@ViewBuilder
	private func chargingGlyph(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
		if let iconName = chargingIconName(for: info) {
			Image(systemName: iconName)
				.font(.system(size: 22, weight: .semibold))
				.foregroundStyle(Color.white)
		} else {
			Image(systemName: "bolt.fill")
				.font(.system(size: 22, weight: .semibold))
				.foregroundStyle(Color.white)
		}
	}

	private func inlineChargingLabel(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if let time = formattedChargingTime(for: info) {
			return time
		}
		return chargingStatusFallback(for: info)
	}

	private func chargingDetailLabel(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		inlineChargingLabel(for: info)
	}

	private func formattedChargingTime(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
		guard let minutes = info.minutesRemaining, minutes > 0 else {
			return nil
		}

		let hours = minutes / 60
		let remainingMinutes = minutes % 60

		if hours > 0 {
			return "\(hours)h \(remainingMinutes)m"
		}
		return "\(remainingMinutes)m"
	}

	private func chargingStatusFallback(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if info.isPluggedIn && !info.isCharging {
			let level = info.batteryLevel.map(clampedBatteryLevel)
			if level == 100 {
				return NSLocalizedString("Fully charged", comment: "Charging fallback label when already charged")
			}
			if let level {
				let onHold = NSLocalizedString("On hold", comment: "Plugged in but charging is paused by the system")
				return "\(level)% • \(onHold)"
			}
			return NSLocalizedString("On hold", comment: "Plugged in but charging is paused by the system")
		}
		return NSLocalizedString("Charging", comment: "Charging fallback label when no estimate is available")
	}

	private func bluetoothPercentageText(for level: Int) -> String {
		"\(clampedBatteryLevel(level))%"
	}

	private func minimumTemperatureLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> String {
		if let minimum = info.displayMinimum {
			return "\(minimum)°"
		}
		return "—"
	}

	private func maximumTemperatureLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> String {
		if let maximum = info.displayMaximum {
			return "\(maximum)°"
		}
		return "—"
	}

	private func temperatureCenterLabel(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> some View {
		return HStack(alignment: .top, spacing: 2) {
			Text("\(info.displayCurrent)°")
				.font(.system(size: 20, weight: .semibold, design: .rounded))
		}
		.foregroundStyle(Color.white)
	}

	private func temperatureRange(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> ClosedRange<Double> {
		let minimumCandidate = info.minimum ?? info.current
		let maximumCandidate = info.maximum ?? info.current
		var lowerBound = min(minimumCandidate, info.current)
		var upperBound = max(maximumCandidate, info.current)

		if lowerBound == upperBound {
			lowerBound -= 1
			upperBound += 1
		}

		return lowerBound...upperBound
	}

	private func clampedBatteryLevel(_ level: Int) -> Int {
		min(max(level, 0), 100)
	}

	private func inlineComposite(primary: String, secondary: String?) -> Text {
		var text = Text(primary).font(inlinePrimaryFont)
		if let secondary, !secondary.isEmpty {
			text = text + Text(" \(secondary)")
				.font(inlineSecondaryFont)
				.foregroundStyle(secondaryLabelColor)
		}
		return text
	}

	private func batteryTint(for level: Int) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<20:
			return Color(.systemRed)
		case 20..<50:
			return Color(.systemOrange)
		default:
			return Color(.systemGreen)
		}
	}

	private func bluetoothTint(for level: Int) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<20:
			return Color(.systemRed)
		case 20..<50:
			return Color(.systemOrange)
		default:
			return Color(.systemGreen)
		}
	}

	private func aqiTint(for info: LockScreenWeatherSnapshot.AirQualityInfo) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		switch info.category {
		case .good:
			return Color(red: 0.20, green: 0.79, blue: 0.39)
		case .fair:
			return Color(red: 0.55, green: 0.85, blue: 0.32)
		case .moderate:
			return Color(red: 0.97, green: 0.82, blue: 0.30)
		case .unhealthyForSensitive:
			return Color(red: 0.98, green: 0.57, blue: 0.24)
		case .unhealthy:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		case .poor:
			return Color(red: 0.98, green: 0.57, blue: 0.24)
		case .veryPoor:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		case .veryUnhealthy:
			return Color(red: 0.65, green: 0.32, blue: 0.86)
		case .extremelyPoor:
			return Color(red: 0.50, green: 0.13, blue: 0.28)
		case .hazardous:
			return Color(red: 0.50, green: 0.13, blue: 0.28)
		case .unknown:
			return Color(red: 0.63, green: 0.66, blue: 0.74)
		}
	}

	private func temperatureTint(for info: LockScreenWeatherSnapshot.TemperatureInfo) -> Color {
		guard snapshot.usesGaugeTint else { return monochromeGaugeTint }
		let value = info.current
		switch value {
		case ..<0:
			return Color(red: 0.29, green: 0.63, blue: 1.00)
		case 0..<15:
			return Color(red: 0.20, green: 0.79, blue: 0.93)
		case 15..<25:
			return Color(red: 0.20, green: 0.79, blue: 0.39)
		case 25..<32:
			return Color(red: 0.97, green: 0.58, blue: 0.29)
		default:
			return Color(red: 0.91, green: 0.29, blue: 0.25)
		}
	}

	private var accessibilityLabel: String {
		var components: [String] = []

		if snapshot.showsLocation, let locationName = snapshot.locationName, !locationName.isEmpty {
			components.append(
				String(
					format: NSLocalizedString("Weather: %@ %@ in %@", comment: "Weather description, temperature, and location"),
					snapshot.description,
					snapshot.temperatureText,
					locationName
				)
			)
		} else {
			components.append(
				String(
					format: NSLocalizedString("Weather: %@ %@", comment: "Weather description and temperature"),
					snapshot.description,
					snapshot.temperatureText
				)
			)
		}

		if let charging = snapshot.charging {
			components.append(accessibilityChargingText(for: charging))
		}

		if let bluetooth = snapshot.bluetooth {
			components.append(accessibilityBluetoothText(for: bluetooth))
		}

		if let airQuality = snapshot.airQuality {
			components.append(accessibilityAirQualityText(for: airQuality))
		}

		if let battery = snapshot.battery, !isInline {
			components.append(accessibilityBatteryText(for: battery))
		}

		if shouldShowFocusWidget {
			components.append("Focus active: \(focusDisplayName)")
		}

		if lockScreenShowCalendarEvent, let event = nextCalendarEvent {
			let line = eventLineText(for: event)
			if !line.isEmpty {
				components.append("Calendar: \(line)")
			}
		}

		return components.joined(separator: ". ")
	}

	private func accessibilityChargingText(for charging: LockScreenWeatherSnapshot.ChargingInfo) -> String {
		if let minutes = charging.minutesRemaining, minutes > 0 {
			let formatter = DateComponentsFormatter()
			formatter.allowedUnits = [.hour, .minute]
			formatter.unitsStyle = .full
			let duration = formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) minutes"
			return String(
				format: NSLocalizedString("Battery charging, %@ remaining", comment: "Charging time remaining"),
				duration
			)
		}

		if charging.isPluggedIn && !charging.isCharging {
			let level = charging.batteryLevel.map(clampedBatteryLevel)
			if level == 100 {
				return NSLocalizedString("Battery fully charged", comment: "Battery is full")
			}
			if let level {
				return String(
					format: NSLocalizedString("Battery at %d percent, charging on hold", comment: "Plugged in but charging is paused by the system"),
					level
				)
			}
			return NSLocalizedString("Charging on hold", comment: "Plugged in but charging is paused by the system")
		}

		if snapshot.showsChargingPercentage, let level = charging.batteryLevel {
			return String(
				format: NSLocalizedString("Battery at %d percent", comment: "Battery percentage"),
				level
			)
		}

		return NSLocalizedString("Battery charging", comment: "Battery charging without estimate")
	}

	private func accessibilityBluetoothText(for bluetooth: LockScreenWeatherSnapshot.BluetoothInfo) -> String {
		String(
			format: NSLocalizedString("Bluetooth device %@ at %d percent", comment: "Bluetooth device battery"),
			bluetooth.deviceName,
			bluetooth.batteryLevel
		)
	}

	private func accessibilityAirQualityText(for airQuality: LockScreenWeatherSnapshot.AirQualityInfo) -> String {
		String(
			format: NSLocalizedString("Air quality index %d, %@", comment: "Air quality accessibility label"),
			airQuality.index,
			"\(airQuality.scale.accessibilityLabel) \(airQuality.category.displayName)"
		)
	}

	private func accessibilityBatteryText(for battery: LockScreenWeatherSnapshot.BatteryInfo) -> String {
		String(
			format: NSLocalizedString("Mac battery at %d percent", comment: "Mac battery gauge accessibility label"),
			clampedBatteryLevel(battery.batteryLevel)
		)
	}

	private func batteryIconName(for level: Int) -> String {
		let clamped = clampedBatteryLevel(level)
		switch clamped {
		case ..<10:
			return "battery.0percent"
		case 10..<40:
			return "battery.25percent"
		case 40..<70:
			return "battery.50percent"
		case 70..<90:
			return "battery.75percent"
		default:
			return "battery.100percent"
		}
	}
}




