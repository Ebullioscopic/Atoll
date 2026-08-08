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

import Defaults
import SwiftUI

enum QuickTimerSlots {
    static let count = 3
    static let `default` = [5, 15, 25]
    static let allowed = 1...180

    static func normalized(_ values: [Int]) -> [Int] {
        var slots = values.map(clamp)
        while slots.count < count {
            slots.append(`default`[slots.count])
        }
        if slots.count > count {
            slots = Array(slots.prefix(count))
        }
        return slots
    }

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, allowed.lowerBound), allowed.upperBound)
    }

    static func label(for minutes: Int) -> String {
        "\(minutes)m"
    }

    static func accessibilityLabel(for minutes: Int) -> String {
        String(format: String(localized: "%d minute timer"), minutes)
    }

    static func start(minutes: Int, presets: [TimerPreset] = Defaults[.timerPresets]) {
        let clamped = clamp(minutes)
        let duration = TimeInterval(clamped * 60)
        let matched = presets.first { Int($0.duration.rounded()) == Int(duration.rounded()) }
        TimerManager.shared.startTimer(
            duration: matched?.duration ?? duration,
            name: matched?.name ?? String(format: String(localized: "%d min"), clamped),
            preset: matched
        )
    }
}

@MainActor
final class QuickTimerPresentationState: ObservableObject {
    static let shared = QuickTimerPresentationState()

    @Published private(set) var isExpanded = false

    func expand() { isExpanded = true }
    func collapse() { isExpanded = false }
    func reset() { isExpanded = false }
}

struct QuickTimerOverlay: View {
    let notchHeight: CGFloat
    let cornerRadius: CGFloat
    var appearToken: UUID = UUID()
    var onStarted: (() -> Void)?

    @Default(.quickTimerMinutes) private var quickTimerMinutes
    @Default(.timerPresets) private var timerPresets
    @ObservedObject private var presentation = QuickTimerPresentationState.shared

    private var slots: [Int] { QuickTimerSlots.normalized(quickTimerMinutes) }
    private var buttonHeight: CGFloat { ClosedNotchSatelliteChrome.buttonHeight(for: notchHeight) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, minutes in
                ClosedNotchChipButton(
                    help: QuickTimerSlots.accessibilityLabel(for: minutes),
                    height: buttonHeight
                ) {
                    Text(QuickTimerSlots.label(for: minutes))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } action: {
                    start(minutes: minutes)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: notchHeight)
        .background { ClosedNotchSatelliteChrome.pillBackground(cornerRadius: cornerRadius) }
        .scaleEffect(
            x: presentation.isExpanded ? 1 : 0.52,
            y: presentation.isExpanded ? 1 : 0.12,
            anchor: .top
        )
        .opacity(presentation.isExpanded ? 1 : 0)
        .fixedSize(horizontal: true, vertical: false)
        .compositingGroup()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Quick timer"))
        .id(appearToken)
        .animation(
            .spring(response: ClosedNotchSatelliteChrome.morphDuration, dampingFraction: 0.8),
            value: presentation.isExpanded
        )
        .onHover { hovering in
#if os(macOS)
            QuickTimerWindowManager.shared.notePointerHover(hovering)
#endif
        }
    }

    private func start(minutes: Int) {
        QuickTimerSlots.start(minutes: minutes, presets: timerPresets)
#if os(macOS)
        QuickTimerWindowManager.shared.hide(animated: true)
#endif
        onStarted?()
    }
}

struct QuickTimerChipPreview: View {
    let minutes: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(QuickTimerSlots.normalized(minutes).enumerated()), id: \.offset) { _, value in
                Text(QuickTimerSlots.label(for: value))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 40, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background { ClosedNotchSatelliteChrome.pillBackground(cornerRadius: 14) }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct QuickTimerMinuteEditor: View {
    @Binding var minutes: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(QuickTimerSlots.label(for: minutes))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            HStack(spacing: 6) {
                editorButton(systemName: "minus") {
                    minutes = QuickTimerSlots.clamp(minutes - 1)
                }
                .disabled(minutes <= QuickTimerSlots.allowed.lowerBound)

                editorButton(systemName: "plus") {
                    minutes = QuickTimerSlots.clamp(minutes + 1)
                }
                .disabled(minutes >= QuickTimerSlots.allowed.upperBound)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func editorButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct ClosedNotchChipButton<Label: View>: View {
    let help: String
    let height: CGFloat
    var emphasized: Bool = false
    @ViewBuilder let label: () -> Label
    let action: () -> Void

    @State private var isHovering = false

    private var radius: CGFloat { max(height * 0.32, 6) }

    private var fill: Color {
        if emphasized {
            return Color.red.opacity(isHovering ? 0.36 : 0.28)
        }
        return Color.white.opacity(isHovering ? 0.18 : 0.10)
    }

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.92))
                .frame(width: 40, height: height)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                )
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}
