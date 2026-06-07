//
//  NotchMixerView.swift
//  DynamicIsland
//
//  Per-app volume mixer tab. UI for the audio engine ported from FineTune
//  (https://github.com/ronitsingh10/FineTune, GPL-3.0, Copyright (c) Ronit Singh).
//
//  All controls are rendered inline — no Menu, no .popover. Controls that
//  spawn their own windows steal focus from the notch panel and trigger its
//  auto-close logic (menus dismissed instantly, popovers never appearing).
//

import SwiftUI
import Defaults

struct NotchMixerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var mixerCoordinator = MixerCoordinator.shared
    @Default(.enableMixerFeature) var enableMixerFeature

    var body: some View {
        Group {
            if !enableMixerFeature {
                MixerPlaceholderView(
                    icon: "slider.horizontal.3",
                    title: "Mixer Disabled",
                    message: "Enable the volume mixer in Settings → Mixer."
                )
            } else if let engine = mixerCoordinator.audioEngine,
                      let permission = mixerCoordinator.permission {
                MixerContentView(engine: engine, permission: permission)
            } else {
                MixerPlaceholderView(
                    icon: "slider.horizontal.3",
                    title: "Starting Mixer…",
                    message: "Setting up the audio engine."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if enableMixerFeature {
                mixerCoordinator.startIfNeeded()
            }
        }
    }
}

// MARK: - Placeholder / empty states

private struct MixerPlaceholderView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.gray)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

// MARK: - Content

private struct MixerContentView: View {
    let engine: AudioEngine
    let permission: AudioRecordingPermission

    var body: some View {
        switch permission.status {
        case .denied:
            VStack(spacing: 8) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Audio capture permission denied")
                    .font(.headline)
                    .foregroundStyle(.white)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unknown:
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.gray)
                Text("Permission required to mix per-app audio")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Grant Permission") {
                    permission.request()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .authorized:
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    MixerDeviceEQBar(engine: engine)
                    if engine.apps.isEmpty {
                        MixerPlaceholderView(
                            icon: "speaker.zzz",
                            title: "No Audio",
                            message: "Apps appear here while they play sound."
                        )
                        .frame(minHeight: 80)
                    } else {
                        ForEach(engine.apps) { app in
                            MixerAppRow(engine: engine, app: app)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - App row

private struct MixerAppRow: View {
    let engine: AudioEngine
    let app: AudioApp

    private enum ExpandedSection {
        case none, routing, eq
    }

    @State private var dragging = false
    @State private var lastDragged = Date.distantPast
    @State private var expanded: ExpandedSection = .none
    @State private var isHovering = false

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(engine.getVolume(for: app)) },
            set: { engine.setVolume(for: app, to: Float($0)) }
        )
    }

    private var isMuted: Bool { engine.getMute(for: app) }
    private var boost: BoostLevel { engine.getBoost(for: app) }
    private var eqActive: Bool {
        let eq = engine.getEQSettings(for: app)
        return eq.isEnabled && (eq.bandGains.contains(where: { $0 != 0 }) || eq.preampDB != 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if expanded == .routing {
                routingSection
            }
            if expanded == .eq {
                MixerEQSection(engine: engine, app: app)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.04))
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)

            Text(app.name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 86, alignment: .leading)

            CustomSlider(
                value: volumeBinding,
                range: 0...1,
                color: isMuted ? .gray : .white,
                dragging: $dragging,
                lastDragged: $lastDragged
            )
            .frame(height: 18)
            .opacity(isMuted ? 0.4 : 1)

            Text("\(Int((engine.getVolume(for: app) * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.gray)
                .frame(width: 34, alignment: .trailing)

            // Mute
            MixerIconButton(
                systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isMuted ? .red : .white.opacity(0.8)
            ) {
                engine.toggleMute(for: app)
            }

            // Boost: cycles 1x → 2x → 3x → 4x → 1x. No menu.
            Button {
                engine.setBoost(for: app, to: boost.next)
            } label: {
                Text(boost.label)
                    .font(.caption2.bold())
                    .foregroundStyle(boost == .x1 ? .white.opacity(0.7) : .orange)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Volume boost — click to cycle")

            // Routing: expands inline device list.
            MixerIconButton(
                systemName: engine.isFollowingDefault(for: app) ? "speaker.circle" : "speaker.circle.fill",
                tint: expanded == .routing ? .blue : (engine.isFollowingDefault(for: app) ? .white.opacity(0.7) : .blue)
            ) {
                withAnimation(.smooth(duration: 0.15)) {
                    expanded = (expanded == .routing) ? .none : .routing
                }
            }

            // EQ: expands inline band editor.
            MixerIconButton(
                systemName: "slider.vertical.3",
                tint: expanded == .eq ? .green : (eqActive ? .green : .white.opacity(0.8))
            ) {
                withAnimation(.smooth(duration: 0.15)) {
                    expanded = (expanded == .eq) ? .none : .eq
                }
            }
        }
    }

    private var routingSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                MixerChip(
                    title: "System Default",
                    selected: engine.isFollowingDefault(for: app)
                ) {
                    engine.setDevice(for: app, deviceUID: nil)
                }
                ForEach(engine.outputDevices, id: \.uid) { device in
                    MixerChip(
                        title: device.name,
                        selected: !engine.isFollowingDefault(for: app)
                            && engine.getDeviceUID(for: app) == device.uid
                    ) {
                        engine.setDevice(for: app, deviceUID: device.uid)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Small controls

private struct MixerIconButton: View {
    let systemName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct MixerChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(selected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Device EQ bar (global EQ per output device)

private struct MixerDeviceEQBar: View {
    let engine: AudioEngine

    @State private var editingDeviceUID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hifispeaker")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Device EQ")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(engine.outputDevices, id: \.uid) { device in
                            let eq = engine.getDeviceEQ(forDeviceUID: device.uid)
                            let active = eq.isEnabled && (eq.bandGains.contains(where: { $0 != 0 }) || eq.preampDB != 0)
                            MixerChip(
                                title: active ? "\(device.name) ●" : device.name,
                                selected: editingDeviceUID == device.uid
                            ) {
                                withAnimation(.smooth(duration: 0.15)) {
                                    editingDeviceUID = (editingDeviceUID == device.uid) ? nil : device.uid
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if let uid = editingDeviceUID {
                MixerEQEditor(
                    get: { engine.getDeviceEQ(forDeviceUID: uid) },
                    set: { engine.setDeviceEQ($0, forDeviceUID: uid) }
                )
                .id(uid)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Inline EQ section (per app)

private struct MixerEQSection: View {
    let engine: AudioEngine
    let app: AudioApp

    var body: some View {
        MixerEQEditor(
            get: { engine.getEQSettings(for: app) },
            set: { engine.setEQSettings($0, for: app) }
        )
    }
}

// MARK: - Shared 10-band editor (+ preamp)

private struct MixerEQEditor: View {
    let get: () -> EQSettings
    let set: (EQSettings) -> Void

    @State private var settings: EQSettings = EQSettings()
    /// Band index being typed into; -1 is the preamp column.
    @State private var editingField: Int?
    @State private var fieldText: String = ""
    @FocusState private var fieldFocused: Bool

    private static let preampIndex = -1
    private static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private static let bandHelp = [
        "31.25 Hz", "62.5 Hz", "125 Hz", "250 Hz", "500 Hz",
        "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz",
    ]
    private static let quickPresets: [EQPreset] = [.flat, .bassBoost, .vocalClarity, .trebleBoost]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                MixerChip(title: settings.isEnabled ? "EQ On" : "EQ Off", selected: settings.isEnabled) {
                    settings.isEnabled.toggle()
                    apply()
                }
                Spacer()
                ForEach(Self.quickPresets, id: \.self) { preset in
                    MixerChip(title: preset.name, selected: false) {
                        settings.bandGains = preset.settings.bandGains
                        settings.isEnabled = true
                        apply()
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Preamp: gain stage before the band filters.
                column(
                    index: Self.preampIndex,
                    value: settings.preampDB,
                    label: "Pre",
                    help: "Preamp — gain applied before the EQ bands (\(Int(EQSettings.minGainDB))…\(Int(EQSettings.maxGainDB)) dB)",
                    accent: .orange,
                    binding: Binding(
                        get: { settings.preampDB },
                        set: { newValue in
                            settings.preampDB = newValue
                            apply()
                        }
                    )
                )

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 64)

                ForEach(0..<EQSettings.bandCount, id: \.self) { band in
                    column(
                        index: band,
                        value: settings.bandGains[band],
                        label: Self.bandLabels[band],
                        help: "\(Self.bandHelp[band]) center — click the value to type an exact gain",
                        accent: .green,
                        binding: Binding(
                            get: { settings.bandGains[band] },
                            set: { newValue in
                                settings.bandGains[band] = newValue
                                apply()
                            }
                        )
                    )
                }
            }
            .opacity(settings.isEnabled ? 1 : 0.35)

            Text("Hz")
                .font(.system(size: 6.5))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 2)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .onAppear {
            settings = get()
        }
    }

    @ViewBuilder
    private func column(
        index: Int,
        value: Float,
        label: String,
        help: String,
        accent: Color,
        binding: Binding<Float>
    ) -> some View {
        VStack(spacing: 2) {
            valueControl(index: index, value: value, accent: accent)
            MixerVerticalSlider(value: binding, range: EQSettings.minGainDB...EQSettings.maxGainDB)
                .frame(width: 14, height: 52)
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(index == Self.preampIndex ? .orange : .secondary)
        }
        .help(help)
    }

    @ViewBuilder
    private func valueControl(index: Int, value: Float, accent: Color) -> some View {
        if editingField == index {
            TextField("", text: $fieldText)
                .textFieldStyle(.plain)
                .font(.system(size: 7).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 26)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                )
                .focused($fieldFocused)
                .onSubmit { commitField() }
                .onExitCommand {
                    editingField = nil
                }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused { commitField() }
                }
        } else {
            Text(gainLabel(value))
                .font(.system(size: 6.5).monospacedDigit())
                .foregroundStyle(value == 0 ? .gray : accent)
                .frame(width: 26)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    fieldText = value == 0 ? "" : String(format: "%.1f", value)
                    editingField = index
                    fieldFocused = true
                }
        }
    }

    private func commitField() {
        guard let index = editingField else { return }
        editingField = nil
        let normalized = fieldText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let typed = Float(normalized), typed.isFinite else { return }
        let clamped = max(EQSettings.minGainDB, min(EQSettings.maxGainDB, typed))
        if index == Self.preampIndex {
            settings.preampDB = clamped
        } else if settings.bandGains.indices.contains(index) {
            settings.bandGains[index] = clamped
        }
        apply()
    }

    private func gainLabel(_ gain: Float) -> String {
        gain == 0 ? "0" : String(format: "%+.1f", gain)
    }

    private func apply() {
        set(settings)
    }
}

// MARK: - Vertical slider

private struct MixerVerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = range.upperBound - range.lowerBound
            let progress = span == 0 ? 0 : CGFloat((value - range.lowerBound) / span)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 4)
                Capsule()
                    .fill(Color.green.opacity(0.8))
                    .frame(width: 4, height: max(2, progress * height))
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .shadow(radius: 1)
                    .offset(y: -(progress * (height - 9)))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = 1 - min(max(drag.location.y / height, 0), 1)
                        value = range.lowerBound + Float(fraction) * span
                    }
            )
            .onTapGesture(count: 2) {
                value = 0
            }
        }
    }
}
