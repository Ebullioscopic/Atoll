//
//  MixerCoordinator.swift
//  DynamicIsland
//
//  Lifecycle owner for the per-app volume mixer engine.
//
//  The audio engine is ported from FineTune (https://github.com/ronitsingh10/FineTune),
//  GPL-3.0, Copyright (c) Ronit Singh. Adapted for Atoll's notch UI.
//
//  The engine is started lazily: only when the Mixer feature is enabled in
//  settings. When disabled, all process taps and aggregate devices are torn
//  down so the app stops touching other apps' audio entirely.
//

import Foundation
import Defaults

@MainActor
final class MixerCoordinator: ObservableObject {
    static let shared = MixerCoordinator()

    /// True while the engine exists. UI gates on this.
    @Published private(set) var isRunning = false

    private(set) var settingsManager: SettingsManager?
    private(set) var autoEQProfileManager: AutoEQProfileManager?
    private(set) var permission: AudioRecordingPermission?
    private(set) var audioEngine: AudioEngine?

    private var crashGuardInstalled = false
    private var defaultsObservationTask: Task<Void, Never>?

    private init() {}

    /// Call once at app launch. Starts the engine if the feature is enabled
    /// and keeps it in sync with the settings toggle from then on.
    func bootstrap() {
        guard defaultsObservationTask == nil else { return }
        defaultsObservationTask = Task { [weak self] in
            for await value in Defaults.updates(.enableMixerFeature) {
                guard let self else { return }
                if value {
                    self.startIfNeeded()
                } else {
                    self.stopIfRunning()
                }
            }
        }
    }

    func startIfNeeded() {
        guard !isRunning else { return }

        if !crashGuardInstalled {
            CrashGuard.install()
            OrphanedTapCleanup.destroyOrphanedDevices()
            crashGuardInstalled = true
        }

        let settings = SettingsManager()
        let autoEQ = AutoEQProfileManager()
        let permission = AudioRecordingPermission()
        let engine = AudioEngine(
            permission: permission,
            settingsManager: settings,
            autoEQProfileManager: autoEQ
        )

        self.settingsManager = settings
        self.autoEQProfileManager = autoEQ
        self.permission = permission
        self.audioEngine = engine
        isRunning = true

        if permission.status == .unknown {
            permission.request()
        }
    }

    func stopIfRunning() {
        guard isRunning else { return }
        audioEngine?.shutdown()
        settingsManager?.flushSync()
        audioEngine = nil
        permission = nil
        autoEQProfileManager = nil
        settingsManager = nil
        isRunning = false
    }

    /// Flush pending settings writes; call from applicationWillTerminate.
    func prepareForTermination() {
        audioEngine?.shutdown()
        settingsManager?.flushSync()
    }
}
