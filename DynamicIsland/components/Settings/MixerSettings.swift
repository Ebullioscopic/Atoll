//
//  MixerSettings.swift
//  DynamicIsland
//
//  Settings pane for the per-app volume mixer (engine ported from FineTune,
//  https://github.com/ronitsingh10/FineTune, GPL-3.0).
//

import SwiftUI
import Defaults

struct MixerSettings: View {
    @ObservedObject private var mixerCoordinator = MixerCoordinator.shared
    @Default(.enableMixerFeature) var enableMixerFeature

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableMixerFeature) {
                    Text("Enable volume mixer")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Adds a Mixer tab to the notch with per-app volume, mute, boost (up to 4x), per-app output routing, and a 10-band equalizer. Requires the System Audio Recording permission to tap each app's audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enableMixerFeature {
                Section {
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text(mixerCoordinator.isRunning ? "Running" : "Stopped")
                            .foregroundStyle(mixerCoordinator.isRunning ? .green : .secondary)
                    }

                    if let permission = mixerCoordinator.permission {
                        HStack {
                            Text("Audio capture permission")
                            Spacer()
                            switch permission.status {
                            case .authorized:
                                Text("Granted").foregroundStyle(.green)
                            case .denied:
                                Button("Open Privacy Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            case .unknown:
                                Button("Grant") {
                                    permission.request()
                                }
                            }
                        }
                    }
                } header: {
                    Text("Status")
                } footer: {
                    Text("Per-app settings (volumes, EQ, routing) persist in Application Support/AtollMixer and are restored when apps reappear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Mixer")
    }
}
