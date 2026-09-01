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
/// Every mode draws inside the notch's normal height. The month grid trades
/// row height for the extra weeks rather than growing the notch: three separate
/// functions compute the notch size and only agree while every tab wants the
/// same height, so a mode that changed it made that disagreement visible --
/// content measured against one height inside a window built for another.
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
            return "Shows the whole month at once. Rows are shorter to fit, so the dates are smaller than in the other views."
        }
    }

    /// Point size for the day numbers.
    ///
    /// Sized against the digits' own height rather than a full line box: dates
    /// have no descenders, so a 13pt date stands about 9pt tall and clears a
    /// 16.8pt month row easily. Budgeting for leading the text never uses is
    /// what kept these smaller than they needed to be.
    var dayFontSize: CGFloat {
        self == .month ? 13 : 14
    }

    /// Spacing between grid rows, tightened for the month so the rows
    /// themselves keep as much of the pane as possible.
    var rowSpacing: CGFloat {
        self == .month ? 1 : 6
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
