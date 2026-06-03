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

import Foundation

class SystemVolumeManager {
    private init() {}

    static func isMuted() -> Bool {
        do {
            return try AppleScriptRunner.run(script: "return output muted of (get volume settings)") == "true"
        } catch {
            NSLog("Error while trying to retrieve muted properties of device: \(error). Returning default value false.")
            return false
        }
    }

    static func getOutputVolume() -> Float {
        do {
            if let volumeStr = Float(try AppleScriptRunner.run(script: "return output volume of (get volume settings)")) {
                return volumeStr / 100
            } else {
                NSLog("Error while trying to parse volume string value. Returning default volume value 1.")
            }
        } catch {
            NSLog("Error while trying to retrieve volume properties of device: \(error). Returning default volume value 1.")
        }
        return 0.01
    }
}
