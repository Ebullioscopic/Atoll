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

#if canImport(AppKit)
import AppKit
private typealias ReminderFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias ReminderFont = UIFont
#endif

struct ReminderLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = ReminderLiveActivityManager.shared

    @Default(.reminderPresentationStyle) private var presentationStyle

    private let wingPadding: CGFloat = 16
    private let ringStrokeWidth: CGFloat = 3

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight)
    }

    var body: some View {
        if let reminder = manager.activeReminder {
            content(for: reminder, now: manager.currentDate)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private func content(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: leftWingWidth, height: notchContentHeight)
                .background(alignment: .leading) {
                    iconSection(for: reminder, now: now)
                        .padding(.leading, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

            Rectangle()
                .fill(.clear)
                .frame(width: vm.closedNotchSize.width, height: notchContentHeight)

            Color.clear
                .frame(width: rightWingWidth(for: reminder, now: now), height: notchContentHeight)
                .background(alignment: .trailing) {
                    rightSection(for: reminder, now: now)
                        .padding(.trailing, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func iconSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        let diameter = iconDiameter
        let accent = accentColor(for: reminder, now: now)

        return Image(systemName: iconName(for: reminder, now: now))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: diameter, height: diameter)
            .frame(width: iconDiameter, height: notchContentHeight, alignment: .center)
    }

    @ViewBuilder
    private func rightSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        let accent = accentColor(for: reminder, now: now)
        switch presentationStyle {
        case .ringCountdown:
            ringCountdownSection(for: reminder, now: now, accent: accent)
        case .digital:
            digitalSection(for: reminder, now: now, accent: accent)
        case .minutes:
            minutesSection(for: reminder, now: now, accent: accent)
        }
    }

    private func ringCountdownSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        let progressValue = progress(for: reminder, now: now)
        let diameter = ringDiameter

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(accent, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progressValue)
        }
        .frame(width: diameter, height: diameter)
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func digitalSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        let countdown = digitalCountdown(for: reminder, now: now)
        return Text(countdown)
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .foregroundColor(accent)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.25), value: countdown)
            .frame(height: notchContentHeight, alignment: .center)
    }

    private func minutesSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(minutesCountdown(for: reminder, now: now))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func progress(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Double {
        guard reminder.leadTime > 0 else { return 1 }
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let elapsed = reminder.leadTime - remaining
        let ratio = elapsed / reminder.leadTime
        return min(max(ratio, 0), 1)
    }

    private func digitalCountdown(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func minutesCountdown(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    private func accentColor(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Color {
        if isCritical(for: reminder, now: now) {
            return .red
        }
        return Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private var leftWingWidth: CGFloat {
        wingPadding + iconDiameter
    }

    private func rightWingWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        var width = wingPadding
        switch presentationStyle {
        case .ringCountdown:
            width += ringDiameter
        case .digital:
            width += countdownWidth(for: reminder, now: now)
        case .minutes:
            width += minutesWidth(for: reminder, now: now)
        }
        return width
    }

    private func countdownWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        let text = digitalCountdown(for: reminder, now: now)
        let width = measureTextWidth(text, font: monospacedDigitFont(size: 16, weight: ReminderFont.Weight.semibold))
        return max(width + 18, 76)
    }

    private func minutesWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        let text = minutesCountdown(for: reminder, now: now)
        let width = measureTextWidth(text, font: systemFont(size: 13, weight: ReminderFont.Weight.semibold))
        return max(width + 18, 88)
    }

    private var iconDiameter: CGFloat {
        max(notchContentHeight - 8, 26)
    }

    private var ringDiameter: CGFloat {
        max(min(notchContentHeight - 12, 22), 16)
    }

    private func measureTextWidth(_ text: String, font: ReminderFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil(NSAttributedString(string: text, attributes: attributes).size().width)
    }

    private func systemFont(size: CGFloat, weight: ReminderFont.Weight) -> ReminderFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #else
        return UIFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    private func monospacedDigitFont(size: CGFloat, weight: ReminderFont.Weight) -> ReminderFont {
        #if canImport(AppKit)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #endif
    }

    private func iconName(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        isCritical(for: reminder, now: now) ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName
    }

    private func isCritical(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = reminder.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }
}
