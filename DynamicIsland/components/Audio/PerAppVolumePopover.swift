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
import SwiftUI

/// Per-app volume sliders for whatever is currently making noise.
struct PerAppVolumePopover: View {
    @ObservedObject private var manager = PerAppVolumeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .padding(.horizontal, -8)

            if manager.isPermissionBlocked {
                permissionCallout
            }

            if manager.apps.isEmpty {
                Text("No apps are playing audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(manager.apps) { app in
                            AppVolumeRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
        .onAppear {
            manager.startTracking()
        }
        .onDisappear {
            manager.stopTracking()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "slider.vertical.3")
                .foregroundStyle(.secondary)
            Text("App Volume")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Reset All") {
                withAnimation(.smooth) {
                    manager.resetAll()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var permissionCallout: some View {
        // A slider that silently does nothing is worse than no slider, so say
        // why rather than leaving the user dragging a dead control.
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Atoll needs audio recording permission to change app volumes.")
                    .font(.caption)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.12))
        .cornerRadius(8)
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp

    @ObservedObject private var manager = PerAppVolumeManager.shared
    @State private var volume: Double = 1.0

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if app.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(PerAppVolumeManager.percentLabel(volume))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $volume, in: 0...1)
                    .controlSize(.mini)
                    .disabled(isMuted)
                    .onChange(of: volume) { _, newValue in
                        manager.setVolume(newValue, for: app.bundleIdentifier)
                    }
            }

            Button {
                manager.setMuted(!isMuted, for: app.bundleIdentifier)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isMuted ? .red : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            // Seeded here rather than in the initialiser: the row is rebuilt
            // whenever the app list refreshes, and re-reading on every rebuild
            // would fight a drag that is still in progress.
            volume = manager.volume(for: app.bundleIdentifier)
        }
    }

    private var isMuted: Bool {
        manager.isMuted(for: app.bundleIdentifier)
    }

    @ViewBuilder
    private var icon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    PerAppVolumePopover()
}
