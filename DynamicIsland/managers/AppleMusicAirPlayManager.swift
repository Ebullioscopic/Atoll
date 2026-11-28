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

struct AirPlayDevice: Identifiable, Equatable {
    let id: String // network address or name as fallback
    let name: String
    let kind: String
    var isSelected: Bool
    var volume: Int // 0-100

    var iconName: String {
        switch kind {
        case "HomePod":
            return "homepodmini"
        case "AirPort Express":
            return "airport.express"
        case "computer":
            return "laptopcomputer"
        case "AirPlay device":
            let normalizedName = name.lowercased()
            if normalizedName.contains("tv") || normalizedName.contains("theatre") || normalizedName.contains("theater") {
                return "appletv"
            }
            return "airplayaudio"
        default:
            return "airplayaudio"
        }
    }
}

@MainActor
final class AppleMusicAirPlayManager: ObservableObject {
    static let shared = AppleMusicAirPlayManager()

    @Published private(set) var devices: [AirPlayDevice] = []
    @Published private(set) var isLoading = false

    private var isBusy = false

    // MARK: - Volume commit pipeline
    // Slider values are written to userSetVolume (non-@Published) and drained
    // at throttled intervals into a serialised AppleScript commit queue.
    // This avoids triggering SwiftUI re-renders that would reset the Slider.

    private var userSetVolume: [String: Int] = [:]
    private var throttleActive: [String: Bool] = [:]
    private var lastCommittedVolume: [String: Int] = [:]
    private var isCommittingVolume = false
    private var pendingVolumeCommits: [(volume: Int, deviceName: String, deviceID: String)] = []

    // MARK: - Device management

    func refreshDevices() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        isLoading = true
        defer { isLoading = false }

        let script = """
        tell application "Music"
            try
                set deviceList to {}
                set allDevices to AirPlay devices
                repeat with d in allDevices
                    set deviceName to name of d
                    set deviceKind to kind of d as string
                    set deviceActive to selected of d
                    set deviceAddr to network address of d
                    set deviceVol to sound volume of d
                    set end of deviceList to {deviceName, deviceKind, deviceActive, deviceAddr, deviceVol}
                end repeat
                return deviceList
            on error
                return {}
            end try
        end tell
        """

        guard let result = try? await AppleScriptHelper.execute(script) else { return }

        let fetched = Self.parseDevices(from: result)
        devices = fetched
        for device in fetched {
            lastCommittedVolume[device.id] = device.volume
        }
    }

    /// Parses the AppleScript device list. Music returns an empty list when it has
    /// no AirPlay devices (or the query fails), so the count can be zero.
    nonisolated static func parseDevices(from result: NSAppleEventDescriptor) -> [AirPlayDevice] {
        let count = result.numberOfItems
        guard count > 0 else { return [] }

        var fetched: [AirPlayDevice] = []
        for i in 1...count {
            guard let item = result.atIndex(i) else { continue }
            let name = item.atIndex(1)?.stringValue ?? "Unknown"
            let kind = item.atIndex(2)?.stringValue ?? "AirPlay device"
            let selected = item.atIndex(3)?.booleanValue ?? false
            let addr = item.atIndex(4)?.stringValue ?? ""
            let volume = Int(item.atIndex(5)?.int32Value ?? 50)
            let id = addr.isEmpty ? name : addr
            fetched.append(AirPlayDevice(id: id, name: name, kind: kind, isSelected: selected, volume: volume))
        }
        return fetched
    }

    func toggleDevice(_ device: AirPlayDevice) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let newState = !device.isSelected
        let escapedName = device.name.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            try
                set targetDevice to first AirPlay device whose name is "\(escapedName)"
                set selected of targetDevice to \(newState)
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
        try? await Task.sleep(for: .milliseconds(200))

        isBusy = false
        await refreshDevices()
    }

    // MARK: - Volume control

    /// Returns the most recent volume the user set for a device, whether it's
    /// still pending, already committed, or (as fallback) the last fetched value.
    func currentVolume(for deviceID: String) -> Int {
        if let pending = userSetVolume[deviceID] { return pending }
        if let committed = lastCommittedVolume[deviceID] { return committed }
        return devices.first { $0.id == deviceID }?.volume ?? 0
    }

    /// Called by the slider on every drag value change.
    /// Does NOT mutate any @Published property — this is critical to prevent
    /// SwiftUI from recreating the slider view and resetting its @State.
    func setVolume(_ volume: Int, for deviceID: String) {
        let clamped = min(max(volume, 0), 100)
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }

        userSetVolume[deviceID] = clamped
        guard throttleActive[deviceID] != true else { return }

        throttleActive[deviceID] = true
        Task { [weak self] in
            guard let self else { return }

            // Commit immediately, then drain at intervals while the user keeps dragging
            if let first = self.userSetVolume.removeValue(forKey: deviceID) {
                await self.enqueueVolumeCommit(volume: first, deviceName: device.name, deviceID: deviceID)
            }

            var alive = true
            while alive {
                try? await Task.sleep(for: .milliseconds(150))
                guard let pending = self.userSetVolume.removeValue(forKey: deviceID) else {
                    alive = false
                    break
                }
                await self.enqueueVolumeCommit(volume: pending, deviceName: device.name, deviceID: deviceID)
            }
            self.throttleActive[deviceID] = false
        }
    }

    // MARK: - Commit queue

    /// Serialises AppleScript calls — only one runs at a time.
    /// Queued entries are deduplicated per-device (only the latest value is kept).
    private func enqueueVolumeCommit(volume: Int, deviceName: String, deviceID: String) async {
        if isCommittingVolume {
            pendingVolumeCommits.removeAll { $0.deviceID == deviceID }
            pendingVolumeCommits.append((volume: volume, deviceName: deviceName, deviceID: deviceID))
            return
        }

        isCommittingVolume = true
        await commitVolume(volume: volume, deviceName: deviceName, deviceID: deviceID)

        while !pendingVolumeCommits.isEmpty {
            var latestByDevice: [String: (volume: Int, deviceName: String, deviceID: String)] = [:]
            for entry in pendingVolumeCommits {
                latestByDevice[entry.deviceID] = entry
            }
            pendingVolumeCommits.removeAll()

            for (_, entry) in latestByDevice {
                await commitVolume(volume: entry.volume, deviceName: entry.deviceName, deviceID: entry.deviceID)
            }
        }
        isCommittingVolume = false
    }

    /// Commits a volume change via AppleScript.
    ///
    /// Apple Music internally rebalances other AirPlay devices when one device's
    /// volume drops past another device's volume in a single call. To prevent this,
    /// when moving DOWN past the highest other selected device's volume, we first
    /// set to that device's volume (waypoint), then to the actual target — at most
    /// two AppleScript calls.
    private func commitVolume(volume: Int, deviceName: String, deviceID: String) async {
        let escapedName = deviceName.replacingOccurrences(of: "\"", with: "\\\"")
        let current = lastCommittedVolume[deviceID] ?? volume

        let otherMaxVolume = devices
            .filter { $0.id != deviceID && $0.isSelected }
            .map { lastCommittedVolume[$0.id] ?? $0.volume }
            .max() ?? 0

        // Waypoint needed when crossing below another device's volume
        if current > otherMaxVolume && volume < otherMaxVolume && otherMaxVolume > 0 {
            await sendVolumeAppleScript(escapedName: escapedName, volume: otherMaxVolume)
        }

        await sendVolumeAppleScript(escapedName: escapedName, volume: volume)
        lastCommittedVolume[deviceID] = volume
    }

    private func sendVolumeAppleScript(escapedName: String, volume: Int) async {
        let script = """
        tell application "Music"
            try
                set targetDevice to first AirPlay device whose name is "\(escapedName)"
                set sound volume of targetDevice to \(volume)
            end try
        end tell
        """
        try? await AppleScriptHelper.executeVoid(script)
    }
}
