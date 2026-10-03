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

import Defaults
import Foundation

/// How much of the calendar the standalone calendar shows at once.
///
/// The mode owns the notch height as well as the date range, because the two
/// cannot disagree: a month needs six week rows and the room to draw them, and
/// three days must not hold the notch open at a month's height. Both are
/// resolved through ``notchTabContentSize``, so the content frame, the window
/// and `vm.notchSize` cannot drift apart over it.
public enum CalendarViewMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case threeDay
    case week
    case month

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .threeDay:
            return String(localized: "3 Days")
        case .week:
            return String(localized: "Week")
        case .month:
            return String(localized: "Month")
        }
    }

    /// Compact label for the picker inside the notch, where the left pane is
    /// roughly half the notch's width and cannot spare room for full words.
    var shortName: String {
        switch self {
        case .threeDay:
            return String(localized: "3D")
        case .week:
            return String(localized: "1W")
        case .month:
            return String(localized: "1M")
        }
    }

    var description: String {
        switch self {
        case .threeDay:
            return "Shows the selected day and the two after it."
        case .week:
            return "Shows the week around the selected day."
        case .month:
            return "Shows the whole month. The notch grows taller to fit every week row without scrolling."
        }
    }

    /// Columns in the day grid, and the number of days a non-month mode spans.
    var dayCount: Int {
        switch self {
        case .threeDay:
            return 3
        case .week, .month:
            return 7
        }
    }

    /// Point size for the day numbers.
    ///
    /// The single-row views get a little more than the month, which divides its
    /// height between five or six rows, but not much: their row is floored at
    /// 74pt by the pane's own minimum rather than by anything the dates need, so
    /// sizing the text to fill it makes the dates the loudest thing in the notch
    /// for no reason. The leftover height reads better as padding around a
    /// normal-sized date than as a reason to enlarge one.
    var dayFontSize: CGFloat {
        self == .month ? 14 : 16
    }

    /// Notch height this mode needs. Only the month grid asks for more than the
    /// default, so picking either of the others returns the notch to its normal
    /// size -- the mode the user chose is the whole story, which is what makes
    /// the taller notch reversible.
    var notchHeight: CGFloat {
        self == .month ? calendarFullMonthNotchHeight : openNotchSize.height
    }

    /// Calendar unit the previous/next buttons step by, so paging moves the
    /// visible range rather than always jumping a month.
    var pagingComponent: Calendar.Component {
        switch self {
        case .threeDay:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }

    var pagingStride: Int {
        switch self {
        case .threeDay:
            return 3
        case .week, .month:
            return 1
        }
    }
}
