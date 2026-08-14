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
import SwiftUI

/// Where the prompter appears.
public enum TeleprompterDisplayMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    /// A detachable floating window. The default, because it is the only surface
    /// big enough to actually read from, and because it does not widen the notch.
    case panel
    /// A tab inside the open notch.
    case tab
    /// Both, so the notch tab acts as a compact view of the same script.
    case both

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .panel: return String(localized: "Floating window")
        case .tab: return String(localized: "Notch tab")
        case .both: return String(localized: "Both")
        }
    }

    var showsNotchTab: Bool {
        self == .tab || self == .both
    }

    var showsPanel: Bool {
        self == .panel || self == .both
    }
}

/// Typeface for the prompter text.
public enum TeleprompterFontChoice: String, CaseIterable, Codable, Sendable, Defaults.Serializable, Identifiable {
    case system
    /// A rounded, wide-tracked system face. Chosen as the accessible default
    /// because Atoll cannot ship OpenDyslexic — committing a font binary is
    /// against the project's rules and would raise a licence question.
    case highLegibility
    /// Used only when the user has installed OpenDyslexic themselves.
    case openDyslexic
    /// Whatever the user picked from the system font list.
    case custom

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .highLegibility: return String(localized: "High legibility")
        case .openDyslexic: return "OpenDyslexic"
        case .custom: return String(localized: "Custom…")
        }
    }

    /// The PostScript family this resolves to, if it needs one installed.
    var requiredFamilyName: String? {
        self == .openDyslexic ? "OpenDyslexic" : nil
    }

    /// Whether the font is actually available to render with.
    var isAvailable: Bool {
        guard let family = requiredFamilyName else { return true }
        return NSFont(name: family, size: 12) != nil
    }
}

/// How the prompter advances through the script.
public enum TeleprompterScrollMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    /// Advances at a fixed words-per-minute.
    case automatic
    /// Only moves when the reader moves it.
    case manual
    /// Follows the reader's voice. Falls back to `manual` when speech
    /// recognition is unavailable or refused.
    case voice

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .manual: return String(localized: "Manual")
        case .voice: return String(localized: "Follow my voice")
        }
    }
}
