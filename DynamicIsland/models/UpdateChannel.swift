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

/// The update channel determines which Sparkle appcast feed the app checks.
enum UpdateChannel: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case stable
    case beta
    case alpha
    case nightly
    case dev

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable:  return String(localized: "Stable")
        case .beta:    return String(localized: "Beta")
        case .alpha:   return String(localized: "Alpha")
        case .nightly: return String(localized: "Nightly")
        case .dev:     return String(localized: "Dev")
        }
    }

    var description: String {
        switch self {
        case .stable:  return String(localized: "Production releases, thoroughly tested")
        case .beta:    return String(localized: "Pre-release builds, mostly stable")
        case .alpha:   return String(localized: "Early testing builds, may have issues")
        case .nightly: return String(localized: "Bleeding edge, built daily from dev")
        case .dev:     return String(localized: "Local development build from Xcode")
        }
    }

    var feedURL: URL {
        let base = "https://raw.githubusercontent.com/Ebullioscopic/Atoll/main/Updates"
        switch self {
        case .stable:  return URL(string: "\(base)/appcast.xml")!
        case .beta:    return URL(string: "\(base)/appcast-beta.xml")!
        case .alpha:   return URL(string: "\(base)/appcast-alpha.xml")!
        case .nightly: return URL(string: "\(base)/appcast-nightly.xml")!
        case .dev:     return URL(string: "\(base)/appcast-nightly.xml")!
        }
    }

    /// A color used for the channel badge in the UI.
    var badgeColor: NSColor {
        switch self {
        case .stable:  return .systemGreen
        case .beta:    return .systemBlue
        case .alpha:   return .systemOrange
        case .nightly: return .systemPurple
        case .dev:     return .systemYellow
        }
    }

    /// An SF Symbol icon for the channel badge.
    var badgeIcon: String {
        switch self {
        case .stable:  return "checkmark.seal.fill"
        case .beta:    return "testtube.2"
        case .alpha:   return "flask.fill"
        case .nightly: return "moon.stars.fill"
        case .dev:     return "hammer.fill"
        }
    }

    /// The channel this build was compiled for.
    /// Debug builds (run from Xcode) are always identified as `.dev`.
    /// Release builds use the `-D` compiler flags set by CI.
    static var buildChannel: UpdateChannel {
        #if DEBUG
        return .dev
        #elseif NIGHTLY
        return .nightly
        #elseif ALPHA
        return .alpha
        #elseif BETA
        return .beta
        #else
        return .stable
        #endif
    }

    /// Channels available for the user to select in Settings.
    /// Dev is excluded since it's only a build-time indicator, not a selectable feed.
    static var availableChannels: [UpdateChannel] {
        return UpdateChannel.allCases.filter { $0 != .dev }
    }
}
