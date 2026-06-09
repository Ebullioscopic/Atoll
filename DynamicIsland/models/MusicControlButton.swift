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

import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case trackBackward
    case playPause
    case trackForward
    case repeatMode
    case mediaOutput
    case airPlay
    case lyrics
    case like
    case seekBackward
    case seekForward
    case none

    static let slotCount = 5

    static let defaultLayout: [MusicControlButton] = [
        .shuffle,
        .trackBackward,
        .playPause,
        .trackForward,
        .repeatMode
    ]

    static let minimalLayout: [MusicControlButton] = [
        .none,
        .trackBackward,
        .playPause,
        .trackForward,
        .none
    ]

    static let pickerOptions: [MusicControlButton] = [
        .trackBackward,
        .playPause,
        .trackForward,
        .seekBackward,
        .seekForward,
        .shuffle,
        .repeatMode,
        .lyrics,
        .like,
        .mediaOutput,
        .airPlay
    ]

    /// Controls that are only available when Apple Music is the active media source.
    var isAppleMusicExclusive: Bool {
        self == .airPlay
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shuffle:
            return String(localized: "Shuffle")
        case .trackBackward:
            return String(localized: "Previous Track")
        case .playPause:
            return String(localized: "Play / Pause")
        case .trackForward:
            return String(localized: "Next Track")
        case .repeatMode:
            return String(localized: "Repeat")
        case .mediaOutput:
            return String(localized: "Change Media Output")
        case .airPlay:
            return String(localized: "AirPlay")
        case .lyrics:
            return String(localized: "Lyrics")
        case .like:
            return String(localized: "Like (Spotify)")
        case .seekBackward:
            return String(localized: "Rewind 10s")
        case .seekForward:
            return String(localized: "Forward 10s")
        case .none:
            return String(localized: "Empty Slot")
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .trackBackward:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .trackForward:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .mediaOutput:
            return "speaker.wave.2"
        case .airPlay:
            return "airplayaudio"
        case .lyrics:
            return "quote.bubble"
        case .like:
            return "heart"
        case .seekBackward:
            return "gobackward.10"
        case .seekForward:
            return "goforward.10"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}

extension Array where Element == MusicControlButton {
    func normalized(allowingMediaOutput: Bool, isAppleMusicActive: Bool = true) -> [MusicControlButton] {
        var sanitized = map { button -> MusicControlButton in
            if button == .mediaOutput && !allowingMediaOutput { return .none }
            if button.isAppleMusicExclusive && !isAppleMusicActive { return .none }
            return button
        }

        if sanitized.count < MusicControlButton.slotCount {
            sanitized.append(contentsOf: Array(repeating: .none, count: MusicControlButton.slotCount - sanitized.count))
        }

        if sanitized.count > MusicControlButton.slotCount {
            sanitized = Array(sanitized.prefix(MusicControlButton.slotCount))
        }

        return sanitized
    }
}

extension MusicControlButton {
    init(auxiliaryControl: MusicAuxiliaryControl) {
        switch auxiliaryControl {
        case .shuffle:
            self = .shuffle
        case .repeatMode:
            self = .repeatMode
        case .mediaOutput:
            self = .mediaOutput
        case .lyrics:
            self = .lyrics
        }
    }
}
