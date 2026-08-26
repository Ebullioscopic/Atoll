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
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var hoveredSlotIndex: Int? = nil
    @State private var targetedSlotIndex: Int? = nil
    @State private var trashDropIsTargeted: Bool = false

    private let slotCount = MusicControlButton.slotCount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            layoutPreview
            Divider()
            palette
            resetButton
        }
        .onAppear {
            ensureSlotCapacity(slotCount)
            removeDisallowedControls()
        }
        .onChange(of: showMediaOutputControl) { _, _ in
            removeDisallowedControls()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Layout Preview")
                .font(.headline)
            Text("Drag items between slots or drop from the palette to remap controls.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var layoutPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<slotCount, id: \.self) { index in
                    slotPreview(for: index)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(trashDropIsTargeted ? Color.red.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(trashDropIsTargeted ? Color.red : .clear, lineWidth: trashDropIsTargeted ? 2 : 0)
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(trashDropIsTargeted ? Color.red : Color.primary)
                }
                .onDrop(of: [UTType.plainText.identifier], isTargeted: $trashDropIsTargeted) { providers in
                    return handleDropOnTrash(providers)
                }

                Text("Clear slot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 72)
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Control Palette")
                    .font(.headline)
                Spacer()
                ScrollHintIndicator()
            }
            Text("Drag a control onto a slot or tap to place it in the first empty slot.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(pickerOptions, id: \.self) { control in
                        paletteItem(for: control)
                    }
                }
                .padding(.top, 4)
                // The horizontal scroll bar is drawn over the bottom of the
                // scroll view's content, not under it, so without a gap of its
                // own it sat across the row beneath.
                .padding(.bottom, 14)
            }
        }
    }

    private var resetButton: some View {
        HStack {
            Spacer()
            Button("Reset to defaults") {
                withAnimation {
                    musicControlSlots = MusicControlButton.defaultLayout
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func slotPreview(for index: Int) -> some View {
        let slot = slotValue(at: index)
        let isHovered = hoveredSlotIndex == index
        let isDropTarget = targetedSlotIndex == index

        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(slotBackgroundColor(isHovered: isHovered, isTargeted: isDropTarget))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(slotBorderColor(isHovered: isHovered, isTargeted: isDropTarget), lineWidth: borderWidth(isHovered: isHovered, isTargeted: isDropTarget))
                )

            slotContent(for: slot)
        }
        .frame(width: 48, height: 48)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isInside in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredSlotIndex = isInside ? index : nil
            }
        }
        .onDrag {
            hoveredSlotIndex = index
            return NSItemProvider(object: NSString(string: "slot:\(index)"))
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: dropTargetBinding(for: index)) { providers in
            return handleDrop(providers, toIndex: index)
        }
    }

    @ViewBuilder
    private func slotContent(for slot: MusicControlButton) -> some View {
        if slot == .none {
            RoundedRectangle(cornerRadius: 6)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary.opacity(0.35))
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: slot.iconName)
                .font(.system(size: slot.prefersLargeScale ? 18 : 15, weight: .medium))
                .foregroundStyle(previewIconColor(for: slot))
        }
    }

    private func isControlDisabled(_ control: MusicControlButton) -> Bool {
        if control == .mediaOutput && !showMediaOutputControl { return true }
        if control.isAppleMusicExclusive && !musicManager.isAppleMusicActive { return true }
        if control.isSpotifyExclusive && !musicManager.isSpotifyActive { return true }
        return false
    }

    private func paletteItem(for control: MusicControlButton) -> some View {
        let disabled = isControlDisabled(control)

        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: control.iconName)
                        .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                        .foregroundStyle(disabled ? .secondary : .primary)
                }
                .onDrag {
                    NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
                }
                .onTapGesture {
                    place(control)
                }

            Text(control.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    private func place(_ control: MusicControlButton) {
        if let emptyIndex = musicControlSlots.firstIndex(of: .none) {
            updateSlot(control, at: emptyIndex)
        } else {
            updateSlot(control, at: 0)
        }
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        let normalized = musicControlSlots.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, isSpotifyActive: musicManager.isSpotifyActive)
        guard normalized.indices.contains(index) else { return .none }
        return normalized[index]
    }

    private var pickerOptions: [MusicControlButton] {
        var base = MusicControlButton.pickerOptions
        if !showMediaOutputControl {
            base = base.filter { $0 != .mediaOutput }
        }
        if !musicManager.isAppleMusicActive {
            base = base.filter { !$0.isAppleMusicExclusive }
        }
        if !musicManager.isSpotifyActive {
            base = base.filter { !$0.isSpotifyExclusive }
        }
        return base
    }

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:
            return musicManager.isShuffled ? .red : .primary
        case .repeatMode:
            return musicManager.repeatMode == .off ? .primary : .red
        case .lyrics:
            return Defaults[.enableLyrics] ? .accentColor : .primary
        case .likeTrack:
            return musicManager.isCurrentTrackLiked == true ? .accentColor : .primary
        default:
            return .primary
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let padding = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: padding))
    }

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                DispatchQueue.main.async {
                    processDropString(raw, toIndex: toIndex)
                }
            }
            return true
        }
        return false
    }

    private func handleDropOnTrash(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                DispatchQueue.main.async {
                    if raw.hasPrefix("slot:"), let index = Int(raw.dropFirst(5)) {
                        clearSlot(at: index)
                    }
                }
            }
            return true
        }
        return false
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        if raw.hasPrefix("slot:"), let source = Int(raw.dropFirst(5)) {
            swapSlot(from: source, to: toIndex)
        } else if raw.hasPrefix("control:"), let control = MusicControlButton(rawValue: String(raw.dropFirst(8))) {
            updateSlot(control, at: toIndex)
        }
    }

    private func clearSlot(at index: Int) {
        guard index >= 0 && index < musicControlSlots.count else { return }
        musicControlSlots[index] = .none
    }

    private func swapSlot(from source: Int, to destination: Int) {
        guard source != destination else { return }
        ensureSlotCapacity(max(source, destination) + 1)
        musicControlSlots.swapAt(source, destination)
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        ensureSlotCapacity(index + 1)
        var current = musicControlSlots
        current[index] = value
        musicControlSlots = current
    }

    private func removeDisallowedControls() {
        if showMediaOutputControl { return }
        let filtered = musicControlSlots.map { $0 == .mediaOutput ? .none : $0 }
        musicControlSlots = filtered
    }

    private func slotBackgroundColor(isHovered: Bool, isTargeted: Bool) -> Color {
        if isTargeted {
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.accentColor.opacity(0.15)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private func slotBorderColor(isHovered: Bool, isTargeted: Bool) -> Color {
        if isTargeted {
            return Color.accentColor
        } else if isHovered {
            return Color.accentColor.opacity(0.8)
        }
        return .clear
    }

    private func borderWidth(isHovered: Bool, isTargeted: Bool) -> CGFloat {
        if isTargeted { return 2 }
        if isHovered { return 1.5 }
        return 0
    }

    private func dropTargetBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { targetedSlotIndex == index },
            set: { newValue in
                if newValue {
                    targetedSlotIndex = index
                } else if targetedSlotIndex == index {
                    targetedSlotIndex = nil
                }
            }
        )
    }
}

/// The "‹ Scroll ›" pill.
///
/// A horizontal row inside a settings form gives no sign that it scrolls --
/// the trackpad has no visible edge to bump against and the scroll bar only
/// appears once somebody has already tried. This says so up front, next to
/// the heading of whatever scrolls.
struct ScrollHintIndicator: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "chevron.left")
            Text("Scroll")
            Image(systemName: "chevron.right")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
