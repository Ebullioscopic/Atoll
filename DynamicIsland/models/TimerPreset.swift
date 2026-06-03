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
import AppKit
import Defaults

struct TimerPreset: Identifiable, Codable, Hashable, Defaults.Serializable {
    struct ColorData: Codable, Hashable, Defaults.Serializable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        init(color: Color) {
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            self.red = nsColor.redComponent
            self.green = nsColor.greenComponent
            self.blue = nsColor.blueComponent
            self.alpha = nsColor.alphaComponent
        }

        var color: Color {
            Color(red: red, green: green, blue: blue, opacity: alpha)
        }
    }

    struct DurationComponents {
        var hours: Int
        var minutes: Int
        var seconds: Int
    }

    var id: UUID
    var name: String
    var duration: TimeInterval
    var colorData: ColorData

    init(id: UUID = UUID(), name: String, duration: TimeInterval, colorData: ColorData) {
        self.id = id
        self.name = name
        self.duration = duration
        self.colorData = colorData
    }

    init(id: UUID = UUID(), name: String, duration: TimeInterval, color: Color) {
        self.init(id: id, name: name, duration: duration, colorData: ColorData(color: color))
    }

    var color: Color {
        colorData.color
    }

    mutating func updateColor(_ newColor: Color) {
        colorData = ColorData(color: newColor)
    }

    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration) ?? "0:00"
    }

    static func components(for duration: TimeInterval) -> DurationComponents {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return DurationComponents(hours: hours, minutes: minutes, seconds: seconds)
    }

    static func duration(from components: DurationComponents) -> TimeInterval {
        TimeInterval(components.hours * 3600 + components.minutes * 60 + components.seconds)
    }

    static let defaultPresets: [TimerPreset] = [
        TimerPreset(name: String(localized: "Focus"), duration: 25 * 60, color: Color.orange),
        TimerPreset(name: String(localized: "Break"), duration: 5 * 60, color: Color.green),
        TimerPreset(name: String(localized: "Deep Work"), duration: 45 * 60, color: Color.purple)
    ]
}
