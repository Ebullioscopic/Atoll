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
import AudioToolbox
import Combine
import CoreAudio
import Defaults
import Foundation
import os.log

private let perAppVolumeLog = OSLog(subsystem: "com.atoll.dynamicisland", category: "PerAppVolume")

/// One app that CoreAudio knows how to play audio for.
struct AudioApp: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let isPlaying: Bool
    let processObjectIDs: [AudioObjectID]

    var id: String { bundleIdentifier }
}

/// Independent volume and mute for each app that is playing audio.
///
/// A tap is only created for an app whose level actually differs from the
/// system default. Apps left at 100% and unmuted keep their normal, untouched
/// path to the output device -- Atoll does not insert itself into the audio of
/// every app on the Mac just to show it in a list.
@MainActor
final class PerAppVolumeManager: ObservableObject {
    static let shared = PerAppVolumeManager()

    /// Apps CoreAudio currently has an audio process for, newest state first
    /// refreshed by `refreshApps()`.
    @Published private(set) var apps: [AudioApp] = []

    /// Set when a tap could not be created because macOS refused the request,
    /// which in practice means audio-recording permission has not been granted.
    @Published private(set) var isPermissionBlocked = false

    private var taps: [String: AppVolumeTap] = [:]
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var pollTimer: Timer?
    private var trackers = 0
    private var featureCancellable: AnyCancellable?

    private init() {
        featureCancellable = Defaults.publisher(.enablePerAppVolume, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    if change.newValue {
                        self.syncTaps()
                    } else {
                        // Leaving taps up with the feature switched off would
                        // keep apps muted with no UI left to unmute them.
                        self.tearDownAllTaps()
                    }
                }
            }
    }

    // MARK: - Stored levels

    func volume(for bundleIdentifier: String) -> Double {
        Defaults[.perAppVolumeLevels][bundleIdentifier] ?? 1.0
    }

    func setVolume(_ volume: Double, for bundleIdentifier: String) {
        let clamped = Self.clampedVolume(volume)
        var levels = Defaults[.perAppVolumeLevels]

        if clamped == 1.0 {
            levels.removeValue(forKey: bundleIdentifier)
        } else {
            levels[bundleIdentifier] = clamped
        }
        Defaults[.perAppVolumeLevels] = levels

        applyLevel(for: bundleIdentifier)
    }

    func isMuted(for bundleIdentifier: String) -> Bool {
        Defaults[.perAppVolumeMuted].contains(bundleIdentifier)
    }

    func setMuted(_ muted: Bool, for bundleIdentifier: String) {
        var mutedApps = Defaults[.perAppVolumeMuted]

        if muted {
            mutedApps.insert(bundleIdentifier)
        } else {
            mutedApps.remove(bundleIdentifier)
        }
        Defaults[.perAppVolumeMuted] = mutedApps

        applyLevel(for: bundleIdentifier)
    }

    /// Returns an app to the system default and drops its tap.
    func reset(_ bundleIdentifier: String) {
        var levels = Defaults[.perAppVolumeLevels]
        levels.removeValue(forKey: bundleIdentifier)
        Defaults[.perAppVolumeLevels] = levels

        var mutedApps = Defaults[.perAppVolumeMuted]
        mutedApps.remove(bundleIdentifier)
        Defaults[.perAppVolumeMuted] = mutedApps

        applyLevel(for: bundleIdentifier)
    }

    func resetAll() {
        Defaults[.perAppVolumeLevels] = [:]
        Defaults[.perAppVolumeMuted] = []
        tearDownAllTaps()
    }

    /// Whether the app has been moved off the system default at all.
    func hasAdjustment(for bundleIdentifier: String) -> Bool {
        Self.needsTap(volume: volume(for: bundleIdentifier), isMuted: isMuted(for: bundleIdentifier))
    }

    // MARK: - Tracking lifecycle

    /// Reference counted so several views can ask for a live app list without
    /// one of them switching polling off while another still needs it.
    func startTracking() {
        trackers += 1
        guard trackers == 1 else { return }

        installListeners()
        refreshApps()
        syncTaps()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshApps() }
        }
    }

    func stopTracking() {
        trackers = max(0, trackers - 1)
        guard trackers == 0 else { return }

        pollTimer?.invalidate()
        pollTimer = nil
        removeListeners()
        // Taps outlive tracking on purpose: a level the user set should keep
        // applying after the popover closes.
    }

    // MARK: - App list

    func refreshApps() {
        guard Defaults[.enablePerAppVolume] else {
            if !apps.isEmpty { apps = [] }
            return
        }

        let runningApplications = NSWorkspace.shared.runningApplications
        let runningIdentifiers = Set(runningApplications.compactMap(\.bundleIdentifier))
        var nameByIdentifier: [String: String] = [:]
        for application in runningApplications {
            if let identifier = application.bundleIdentifier, let name = application.localizedName {
                nameByIdentifier[identifier] = name
            }
        }

        var processesByIdentifier: [String: [AudioObjectID]] = [:]
        var playingIdentifiers: Set<String> = []

        for processObject in AudioProcessQuery.processObjectIDs() {
            guard let rawIdentifier = AudioProcessQuery.bundleIdentifier(for: processObject) else { continue }

            let identifier = Self.canonicalBundleIdentifier(rawIdentifier, among: runningIdentifiers)
            // Atoll's own output would mean tapping ourselves.
            guard identifier != Bundle.main.bundleIdentifier else { continue }

            processesByIdentifier[identifier, default: []].append(processObject)
            if AudioProcessQuery.isRunningOutput(processObject) {
                playingIdentifiers.insert(identifier)
            }
        }

        let refreshed = processesByIdentifier.map { identifier, processObjects in
            AudioApp(
                bundleIdentifier: identifier,
                name: nameByIdentifier[identifier] ?? Self.fallbackName(for: identifier),
                isPlaying: playingIdentifiers.contains(identifier),
                processObjectIDs: processObjects.sorted()
            )
        }

        let sorted = Self.sorted(refreshed, adjusted: { [weak self] in self?.hasAdjustment(for: $0) ?? false })
        if sorted != apps {
            apps = sorted
        }

        syncTaps()
    }

    // MARK: - Taps

    private func applyLevel(for bundleIdentifier: String) {
        if let tap = taps[bundleIdentifier] {
            tap.gain = Self.effectiveGain(
                volume: volume(for: bundleIdentifier),
                isMuted: isMuted(for: bundleIdentifier)
            )
        }
        syncTaps()
    }

    /// Brings the set of live taps in line with the stored levels and the apps
    /// that are currently playing.
    private func syncTaps() {
        guard Defaults[.enablePerAppVolume] else {
            tearDownAllTaps()
            return
        }

        guard let deviceID = AudioProcessQuery.defaultOutputDeviceID(),
              let deviceUID = AudioProcessQuery.deviceUID(deviceID) else {
            tearDownAllTaps()
            return
        }

        let processesByIdentifier = Dictionary(
            uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0.processObjectIDs) }
        )

        // Drop taps that are no longer wanted, whose app has gone away, or
        // whose process set or output device has changed underneath them.
        for (identifier, tap) in taps {
            let stillWanted = hasAdjustment(for: identifier)
            let processObjects = processesByIdentifier[identifier]
            let unchanged = tap.processObjectIDs == processObjects && tap.outputDeviceUID == deviceUID

            if !stillWanted || processObjects == nil || !unchanged {
                tap.invalidate()
                taps.removeValue(forKey: identifier)
            }
        }

        for app in apps {
            let identifier = app.bundleIdentifier
            guard hasAdjustment(for: identifier), taps[identifier] == nil, !app.processObjectIDs.isEmpty else {
                continue
            }

            do {
                let tap = try AppVolumeTap(
                    bundleIdentifier: identifier,
                    processObjectIDs: app.processObjectIDs,
                    outputDeviceUID: deviceUID
                )
                tap.gain = Self.effectiveGain(volume: volume(for: identifier), isMuted: isMuted(for: identifier))
                try tap.activate()
                taps[identifier] = tap
                isPermissionBlocked = false
            } catch {
                os_log(.error, log: perAppVolumeLog, "Could not tap %{public}@: %{public}@",
                       identifier, String(describing: error))
                // A refused tap is almost always the audio-recording prompt not
                // having been accepted, so surface it rather than silently
                // leaving the slider with no effect.
                isPermissionBlocked = true
            }
        }
    }

    private func tearDownAllTaps() {
        for tap in taps.values {
            tap.invalidate()
        }
        taps.removeAll()
    }

    // MARK: - Listeners

    private func installListeners() {
        guard processListListener == nil else { return }

        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let processListBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refreshApps() }
        }
        if AudioObjectAddPropertyListenerBlock(systemObject, &processListAddress, .main, processListBlock) == noErr {
            processListListener = processListBlock
        }

        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultDeviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                // Every aggregate is built around a specific output device, so
                // switching output has to rebuild them all.
                self?.tearDownAllTaps()
                self?.syncTaps()
            }
        }
        if AudioObjectAddPropertyListenerBlock(systemObject, &defaultDeviceAddress, .main, defaultDeviceBlock) == noErr {
            defaultDeviceListener = defaultDeviceBlock
        }
    }

    private func removeListeners() {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)

        if let processListListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, processListListener)
            self.processListListener = nil
        }

        if let defaultDeviceListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &address, .main, defaultDeviceListener)
            self.defaultDeviceListener = nil
        }
    }

    // MARK: - Pure helpers

    nonisolated static func clampedVolume(_ volume: Double) -> Double {
        min(max(volume, 0), 1)
    }

    /// The gain the tap should apply. Muting wins over the slider, so a muted
    /// app stays silent when its level is changed.
    nonisolated static func effectiveGain(volume: Double, isMuted: Bool) -> Float {
        isMuted ? 0 : Float(clampedVolume(volume))
    }

    /// Whether this app needs a tap at all. An app at full volume and unmuted
    /// is left alone.
    nonisolated static func needsTap(volume: Double, isMuted: Bool) -> Bool {
        isMuted || clampedVolume(volume) != 1.0
    }

    nonisolated static func percentLabel(_ volume: Double) -> String {
        "\(Int((clampedVolume(volume) * 100).rounded()))%"
    }

    /// Rolls a helper process up to the app the user actually recognises.
    ///
    /// CoreAudio reports browser and player helpers under their own bundle IDs
    /// -- `com.tidal.desktop.player`, `com.google.Chrome.helper` -- which would
    /// otherwise show up as separate, unrecognisable rows next to the real app.
    nonisolated static func canonicalBundleIdentifier(
        _ identifier: String,
        among runningIdentifiers: Set<String>
    ) -> String {
        if runningIdentifiers.contains(identifier) { return identifier }

        // Longest matching ancestor wins, so `com.foo.bar.helper` prefers
        // `com.foo.bar` over `com.foo` when both are running.
        var components = identifier.split(separator: ".").map(String.init)
        var best: String?

        while components.count > 1 {
            components.removeLast()
            let candidate = components.joined(separator: ".")
            if runningIdentifiers.contains(candidate) {
                best = candidate
                break
            }
        }

        return best ?? identifier
    }

    /// Playing apps first, then apps the user has already adjusted, then the
    /// rest alphabetically -- so the row someone opened the popover to reach is
    /// at the top.
    nonisolated static func sorted(_ apps: [AudioApp], adjusted: (String) -> Bool) -> [AudioApp] {
        apps.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }

            let lhsAdjusted = adjusted(lhs.bundleIdentifier)
            let rhsAdjusted = adjusted(rhs.bundleIdentifier)
            if lhsAdjusted != rhsAdjusted { return lhsAdjusted }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Last resort label for an app that is not in `runningApplications`.
    nonisolated static func fallbackName(for identifier: String) -> String {
        identifier.split(separator: ".").last.map(String.init) ?? identifier
    }
}
