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

import Combine
import Defaults
import Foundation
import CoreGraphics
import SwiftUI
import AppKit
import os

@MainActor
final class ReminderLiveActivityManager: ObservableObject {
    struct ReminderEntry: Equatable {
        let event: EventModel
        let triggerDate: Date
        let leadTime: TimeInterval
    }

    static let shared = ReminderLiveActivityManager()
    static let standardIconName = "calendar.badge.clock"
    static let criticalIconName = "calendar.badge.exclamationmark"
    static let listRowHeight: CGFloat = 30
    static let listRowSpacing: CGFloat = 8
    static let listTopPadding: CGFloat = 14
    static let listBottomPadding: CGFloat = 10
    static let baselineMinimalisticBottomPadding: CGFloat = 3

    @Published private(set) var activeReminder: ReminderEntry?
    @Published private(set) var currentDate: Date = Date()
    @Published private(set) var upcomingEntries: [ReminderEntry] = []
    @Published private(set) var activeWindowReminders: [ReminderEntry] = []
    @Published private(set) var lockScreenSnapshot: LockScreenReminderWidgetSnapshot?

    private let logger: os.Logger = os.Logger(subsystem: "com.ebullioscopic.Atoll", category: "ReminderLiveActivity")

    private var nextReminder: ReminderEntry?
    private var cancellables = Set<AnyCancellable>()
    private var tickerTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var evaluationTask: Task<Void, Never>?
    private var hasShownCriticalSneakPeek = false
    private var latestEvents: [EventModel] = []
    private var pendingEventsSnapshot: [EventModel]? = nil
    private var pendingEventsSignature: Int?
    private var lastEventsSignature: Int?
    private var eventsUpdateDebounceTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var upcomingComputationTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private let eventsDebounceInterval: TimeInterval = 0.35
    private var settingsUpdateTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var pendingSettingsAction: (() -> Void)?
    private var pendingSettingsReason: String?
    private let settingsUpdateDebounceInterval: TimeInterval = 0.2
    private var suppressUpdatesForLock = false
    private var deferredLockResumeTask: Task<Void, Never>? { didSet { oldValue?.cancel() } }
    private var nextAllowedLockResumeRefresh: Date = .distantPast
    private let lockResumeCooldown: TimeInterval = 5
    private let lockScreenTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var lastAppliedLeadTime = Defaults[.reminderLeadTime]
    private var lastAppliedHideAllDay = Defaults[.hideAllDayEvents]
    private var lastAppliedHideCompleted = Defaults[.hideCompletedReminders]

    private let calendarManager = CalendarManager.shared

    var isActive: Bool { activeReminder != nil }

    private init() {
        latestEvents = calendarManager.events
        lastEventsSignature = makeEventsSignature(for: latestEvents)
        setupObservers()
        if !latestEvents.isEmpty {
            recalculateUpcomingEntries(reason: "initialization")
        }
    }

    private func setupObservers() {
        Defaults.publisher(.enableReminderLiveActivity, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.recalculateUpcomingEntries(reason: "defaults-toggle")
                } else {
                    self.deactivateReminder()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderLeadTime, options: [])
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedLeadTime else { return }
                self.scheduleSettingsRecalculation(reason: "lead-time") {
                    self.lastAppliedLeadTime = newValue
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideAllDayEvents, options: [])
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedHideAllDay else { return }
                self.scheduleSettingsRecalculation(reason: "hide-all-day") {
                    self.lastAppliedHideAllDay = newValue
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.hideCompletedReminders, options: [])
            .map(\.newValue)
            .sink { [weak self] newValue in
                guard let self else { return }
                guard newValue != self.lastAppliedHideCompleted else { return }
                self.scheduleSettingsRecalculation(reason: "hide-completed") {
                    self.lastAppliedHideCompleted = newValue
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.reminderPresentationStyle, options: [])
            .sink { [weak self] _ in
                guard let self else { return }
                // Presentation change does not alter scheduling, but ensure state publishes for UI updates.
                if let reminder = self.activeReminder {
                    self.activeReminder = reminder
                }
            }
            .store(in: &cancellables)

        calendarManager.$events
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] events in
                self?.handleCalendarEventsUpdate(events)
            }
            .store(in: &cancellables)

        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                self?.handleLockStateChange(isLocked: locked)
            }
            .store(in: &cancellables)
    }

    private func scheduleSettingsRecalculation(reason: String, action: @escaping () -> Void) {
        pendingSettingsAction = action
        pendingSettingsReason = reason
        settingsUpdateTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(settingsUpdateDebounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                Logger.log("settingsUpdateTask cancelled after sleep", category: .debug)
                return
            }
            await self.applyPendingSettingsRecalculation()
        }
    }

    @MainActor
    private func applyPendingSettingsRecalculation() {
        guard let action = pendingSettingsAction, let reason = pendingSettingsReason else { return }
        pendingSettingsAction = nil
        pendingSettingsReason = nil
        action()
        recalculateUpcomingEntries(reason: reason)
    }

    private func cancelAllTimers() {
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        hasShownCriticalSneakPeek = false
    }

    private func deactivateReminder() {
        nextReminder = nil
        activeReminder = nil
        upcomingEntries = []
        activeWindowReminders = []
        cancelAllTimers()
        lockScreenSnapshot = nil
    }

    private func handleCalendarEventsUpdate(_ events: [EventModel]) {
        let signature = makeEventsSignature(for: events)
        if let pendingEventsSignature, pendingEventsSignature == signature {
            pendingEventsSnapshot = events
            return
        }
        if let lastEventsSignature, lastEventsSignature == signature {
            return
        }
        pendingEventsSnapshot = events
        pendingEventsSignature = signature
        guard !suppressUpdatesForLock else { return }
        schedulePendingEventsSnapshotApplication()
    }

    private func schedulePendingEventsSnapshotApplication() {
        eventsUpdateDebounceTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(eventsDebounceInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self.applyPendingEventsSnapshot()
        }
    }

    @MainActor
    private func applyPendingEventsSnapshot() {
        guard !suppressUpdatesForLock else { return }
        guard let snapshot = pendingEventsSnapshot else { return }
        pendingEventsSnapshot = nil
        let previousEvents = latestEvents
        latestEvents = snapshot
        if let pendingEventsSignature {
            lastEventsSignature = pendingEventsSignature
            self.pendingEventsSignature = nil
        } else {
            lastEventsSignature = makeEventsSignature(for: snapshot)
        }

        guard snapshot != previousEvents else { return }
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }
        logger.debug("[Reminder] Applying calendar snapshot update (events=\(snapshot.count, privacy: .public))")
        recalculateUpcomingEntries(reason: "calendar-events")
    }

    private func handleLockStateChange(isLocked: Bool) {
        Logger.log("Lock state changed: \(isLocked)", category: .lifecycle)
        suppressUpdatesForLock = isLocked
        if isLocked {
            eventsUpdateDebounceTask = nil
            upcomingComputationTask = nil
            settingsUpdateTask = nil
            pendingSettingsAction = nil
            pendingSettingsReason = nil
            pauseReminderActivityForLock()
            deferredLockResumeTask = nil
        } else {
            resumeAfterLockIfNeeded()
        }
    }

    private func pauseReminderActivityForLock() {
        Logger.log("Pausing reminder activity for lock", category: .lifecycle)
        tickerTask = nil
        evaluationTask?.cancel()
        evaluationTask = nil
    }

    private func resumeAfterLockIfNeeded() {
        Logger.log("Resuming reminder activity after lock", category: .lifecycle)
        let now = Date()
        if now < nextAllowedLockResumeRefresh {
            let delay = nextAllowedLockResumeRefresh.timeIntervalSince(now)
            scheduleDeferredLockResume(after: delay)
            return
        }
        performLockResumeRefresh()
    }

    private func scheduleDeferredLockResume(after delay: TimeInterval) {
        guard delay > 0 else {
            performLockResumeRefresh()
            return
        }
        deferredLockResumeTask = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else {
                Logger.log("deferredLockResumeTask cancelled after sleep", category: .debug)
                return
            }
            await MainActor.run {
                self?.performLockResumeRefresh()
            }
        }
    }

    @MainActor
    private func performLockResumeRefresh() {
        deferredLockResumeTask = nil
        nextAllowedLockResumeRefresh = Date().addingTimeInterval(lockResumeCooldown)
        if pendingEventsSnapshot != nil {
            schedulePendingEventsSnapshotApplication()
        } else {
            Task { [weak self] in
                await self?.evaluateCurrentState(at: Date(), source: "performLockResumeRefresh")
            }
        }
    }

    private func recalculateUpcomingEntries(referenceDate: Date = Date(), reason: String) {
        Logger.log("Recalculating upcoming entries. Reason: \(reason)", category: .debug)
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }
        let snapshot = latestEvents
        let leadMinutes = Defaults[.reminderLeadTime]
        let hideAllDay = Defaults[.hideAllDayEvents]
        let hideCompleted = Defaults[.hideCompletedReminders]

        upcomingComputationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            let upcoming = Self.buildUpcomingEntries(
                events: snapshot,
                leadMinutes: leadMinutes,
                referenceDate: referenceDate,
                hideAllDayEvents: hideAllDay,
                hideCompletedReminders: hideCompleted
            )
            guard !Task.isCancelled else { return }
            await self.publishUpcomingEntries(upcoming, referenceDate: referenceDate, reason: reason)
        }
    }

    @MainActor
    private func publishUpcomingEntries(_ upcoming: [ReminderEntry], referenceDate: Date, reason: String) {
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        upcomingEntries = upcoming
        updateActiveWindowReminders(for: referenceDate)

        guard let first = upcoming.first else {
            clearActiveReminderState()
            logger.debug("[Reminder] No upcoming reminders found (reason=\(reason, privacy: .public))")
            return
        }

        logger.debug("[Reminder] Next reminder ‘\(first.event.title, privacy: .public)’ (reason=\(reason, privacy: .public))")
        handleEntrySelection(first, referenceDate: referenceDate)
    }

    nonisolated private static func buildUpcomingEntries(
        events: [EventModel],
        leadMinutes: Int,
        referenceDate: Date,
        hideAllDayEvents: Bool,
        hideCompletedReminders: Bool
    ) -> [ReminderEntry] {
        guard !Task.isCancelled else { return [] }
        let leadSeconds = max(1, leadMinutes) * 60
        var entries: [ReminderEntry] = []
        entries.reserveCapacity(events.count)
        for event in events {
            if Task.isCancelled { return [] }
            if hideAllDayEvents && event.isAllDay {
                continue
            }
            if hideCompletedReminders,
               case let .reminder(completed) = event.type,
               completed {
                continue
            }
            guard event.start > referenceDate else { continue }
            let trigger = event.start.addingTimeInterval(TimeInterval(-leadSeconds))
            entries.append(.init(event: event, triggerDate: trigger, leadTime: TimeInterval(leadSeconds)))
        }
        return entries.sorted { $0.triggerDate < $1.triggerDate }
    }

    private func clearActiveReminderState() {
        nextReminder = nil
        if activeReminder != nil {
            activeReminder = nil
        }
        activeWindowReminders = []
        cancelAllTimers()
    }

    private func scheduleEvaluation(at date: Date) {
        evaluationTask?.cancel()
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            Task { await self.evaluateCurrentState(at: Date(), source: "scheduleEvaluation-immediate") }
            return
        }

        evaluationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else {
                Logger.log("scheduleEvaluation task cancelled after sleep", category: .debug)
                return
            }
            await self.evaluateCurrentState(at: Date(), source: "scheduleEvaluation-delayed")
        }
    }

    private func startTickerIfNeeded() {
        guard tickerTask == nil else { return }
        Logger.log("Starting ticker", category: .debug)
        tickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.handleTick()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func handleEntrySelection(_ entry: ReminderEntry?, referenceDate: Date) {
        Logger.log("handleEntrySelection called for \(entry?.event.title ?? "nil")", category: .debug)
        guard nextReminder != entry else {
            Logger.log("handleEntrySelection: entry matches nextReminder, forcing evaluation", category: .debug)
            Task { await self.evaluateCurrentState(at: referenceDate, source: "handleEntrySelection-force") }
            return
        }

        nextReminder = entry
        hasShownCriticalSneakPeek = false
        Task { await self.evaluateCurrentState(at: referenceDate, source: "handleEntrySelection-change") }
    }

    func evaluateCurrentState(at date: Date, source: String = "unknown") async {
        Logger.log("evaluateCurrentState at \(date) from \(source)", category: .debug)
        guard Defaults[.enableReminderLiveActivity] else {
            deactivateReminder()
            return
        }

        defer { publishLockScreenSnapshot(referenceDate: date) }

        currentDate = date
        updateActiveWindowReminders(for: date)

        guard var entry = nextReminder else {
            if activeReminder != nil {
                activeReminder = nil
            }
            stopTicker()
            hasShownCriticalSneakPeek = false
            return
        }

        if entry.event.start <= date {
            clearActiveReminderState()
            Logger.log("[Reminder] Reminder reached start time; advancing to next reminder", category: .debug)
            
            // Robustly remove all expired entries.
            // Note: We use event.start <= date instead of matching entry.id because
            // entry might be a modified copy (with different triggerDate) that doesn't match
            // the one in upcomingEntries, which would cause index lookup to fail and lead to an infinite loop.
            upcomingEntries.removeAll { $0.event.start <= date }
            
            if let next = upcomingEntries.first {
                handleEntrySelection(next, referenceDate: date)
            } else {
                Logger.log("[Reminder] No more upcoming reminders after expiration", category: .debug)
            }
            return
        }

        if entry.triggerDate <= date {
            if entry.triggerDate > entry.event.start {
                entry = ReminderEntry(event: entry.event, triggerDate: entry.event.start, leadTime: entry.leadTime)
                nextReminder = entry
            }
            if activeReminder != entry {
                activeReminder = entry
                DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .reminder,
                    duration: Defaults[.reminderSneakPeekDuration],
                    value: 0,
                    icon: ReminderLiveActivityManager.standardIconName
                )
                hasShownCriticalSneakPeek = false
            }

            let criticalWindow = TimeInterval(Defaults[.reminderSneakPeekDuration])
            let timeRemaining = entry.event.start.timeIntervalSince(date)
            if criticalWindow > 0 && timeRemaining > 0 {
                if timeRemaining <= criticalWindow {
                    if !hasShownCriticalSneakPeek {
                        let displayDuration = min(criticalWindow, max(timeRemaining - 2, 0))
                        if displayDuration > 0 {
                            DynamicIslandViewCoordinator.shared.toggleSneakPeek(
                                status: true,
                                type: .reminder,
                                duration: displayDuration,
                                value: 0,
                                icon: ReminderLiveActivityManager.criticalIconName
                            )
                            hasShownCriticalSneakPeek = true
                        }
                    }
                } else {
                    hasShownCriticalSneakPeek = false
                }
            }
            startTickerIfNeeded()
        } else {
            if activeReminder != nil {
                activeReminder = nil
            }
            stopTicker()
            hasShownCriticalSneakPeek = false
            scheduleEvaluation(at: entry.triggerDate)
        }
    }

    @MainActor
    private func handleTick() async {
        // Logger.log("Tick", category: .debug) // Too verbose
        let now = Date()
        if abs(currentDate.timeIntervalSince(now)) >= 0.5 {
            currentDate = now
        }
        await evaluateCurrentState(at: now, source: "handleTick")
    }

    private func updateActiveWindowReminders(for date: Date) {
        let filtered = upcomingEntries.filter { entry in
            entry.triggerDate <= date && entry.event.start >= date
        }
        if filtered != activeWindowReminders {
            logger.debug("[Reminder] Active window reminder count -> \(filtered.count, privacy: .public)")
            activeWindowReminders = filtered
        }
    }

    private func publishLockScreenSnapshot(referenceDate: Date) {
        guard Defaults[.enableLockScreenReminderWidget] else {
            if lockScreenSnapshot != nil {
                lockScreenSnapshot = nil
            }
            return
        }
        guard let entry = activeReminder else {
            if lockScreenSnapshot != nil {
                lockScreenSnapshot = nil
            }
            return
        }

        let snapshot = buildLockScreenSnapshot(for: entry, now: referenceDate)
        if lockScreenSnapshot != snapshot {
            Logger.log("Publishing new lock screen snapshot: \(snapshot.title)", category: .debug)
            lockScreenSnapshot = snapshot
        }
    }

    private func buildLockScreenSnapshot(for entry: ReminderEntry, now: Date) -> LockScreenReminderWidgetSnapshot {
        let title = entry.event.title.isEmpty ? "Upcoming Reminder" : entry.event.title
        let isCritical = lockScreenCriticalWindowContains(entry: entry, now: now)
        return LockScreenReminderWidgetSnapshot(
            title: title,
            eventTimeText: lockScreenTimeFormatter.string(from: entry.event.start),
            relativeDescription: lockScreenRelativeDescription(for: entry, now: now),
            accent: lockScreenAccentColor(for: entry, isCritical: isCritical),
            chipStyle: Defaults[.lockScreenReminderChipStyle],
            isCritical: isCritical,
            iconName: isCritical ? Self.criticalIconName : Self.standardIconName
        )
    }

    private func lockScreenAccentColor(for entry: ReminderEntry, isCritical: Bool) -> LockScreenReminderWidgetSnapshot.RGBAColor {
        if isCritical {
            return .init(nsColor: .systemRed)
        }

        let boosted = Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
        return .init(nsColor: NSColor(boosted))
    }

    private func lockScreenRelativeDescription(for entry: ReminderEntry, now: Date) -> String? {
        let remaining = entry.event.start.timeIntervalSince(now)
        if remaining <= 0 {
            return String(format: String(localized: "now"))
        }

        let minutes = Int(ceil(remaining / 60))
        switch minutes {
        case ..<1:
            return String(format: String(localized: "now"))
        case 1:
            return String(format: String(localized: "in %@"), String(localized: "1 min"))
        default:
            return "\(String(format: String(localized: "in \(minutes)"))) \(String(format: String(localized: "min")))"
        }
    }

    private func lockScreenCriticalWindowContains(entry: ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = entry.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }

    static func additionalHeight(forRowCount rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let rows = CGFloat(rowCount)
        let spacing = CGFloat(max(rowCount - 1, 0)) * listRowSpacing
        let bottomDelta = max(listBottomPadding - baselineMinimalisticBottomPadding, 0)
        return listTopPadding + rows * listRowHeight + spacing + bottomDelta
    }

}

extension ReminderLiveActivityManager {
    private func makeEventsSignature(for events: [EventModel]) -> Int {
        var hasher = Hasher()
        hasher.combine(events.count)
        for event in events {
            hasher.combine(event.id)
            hasher.combine(event.title)
            hasher.combine(event.start.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(event.end.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(event.isAllDay)
            hasher.combine(event.calendar.id)
            hasher.combine(event.location ?? "")
            switch event.type {
            case .reminder(let completed):
                hasher.combine(0)
                hasher.combine(completed)
            case .event(let attendance):
                hasher.combine(1)
                hasher.combine(hashValue(for: attendance))
            case .birthday:
                hasher.combine(2)
            }
        }
        return hasher.finalize()
    }

    private func hashValue(for status: AttendanceStatus) -> Int {
        switch status {
        case .accepted:
            return 1
        case .maybe:
            return 2
        case .pending:
            return 3
        case .declined:
            return 4
        case .unknown:
            return 5
        }
    }
}

extension ReminderLiveActivityManager.ReminderEntry: Identifiable {
    var id: String { event.id }
}
