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

/// The Prompter tab: the script, plus enough controls to run a take without
/// opening the floating window.
struct NotchTeleprompterView: View {
    @ObservedObject private var manager = TeleprompterManager.shared
    @ObservedObject private var panelManager = TeleprompterPanelManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    /// The notch closes on an upward scroll, which would otherwise make the
    /// script impossible to scroll through.
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    @Default(.teleprompterFontSize) private var fontSize
    @Default(.teleprompterFontChoice) private var fontChoice
    @Default(.teleprompterCustomFontFamily) private var customFontFamily
    @Default(.teleprompterMirrored) private var isMirrored

    @State private var isPasting = false
    @State private var pastedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let take = manager.lastTake {
                // The debrief is the point of the take, so it leads.
                TeleprompterDebriefView(
                    take: take,
                    script: manager.currentScript,
                    onDismiss: { manager.dismissDebrief() }
                )
            } else if isPasting {
                pasteField
            } else if let script = manager.currentScript {
                TeleprompterScriptTextView(
                    script: script,
                    confirmedTokenIndex: manager.confirmedTokenIndex,
                    // Smaller in the notch, which is a glance rather than a page.
                    fontSize: max(13, fontSize * 0.6),
                    fontChoice: fontChoice,
                    customFontFamily: customFontFamily,
                    isMirrored: isMirrored,
                    isCompact: true,
                    coveredSectionIndices: manager.coveredSectionIndices
                )
                sectionRail(script)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .onHover { updateSuppression(for: $0) }
        .onDisappear { updateSuppression(for: false) }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Prompter")
                .font(.system(size: 13, weight: .semibold))

            if let script = manager.currentScript {
                Text(script.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Knowing what follows is the whole reason to have a running order:
            // it tells you the prompter will keep going without you.
            if let next = manager.nextInPlaylist {
                HStack(spacing: 3) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    Text(next.name)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.white.opacity(0.10), in: Capsule())
                .foregroundStyle(.secondary)
                .help(Text("Next in the running order"))
            }

            Spacer(minLength: 0)

            if manager.currentScript != nil {
                Button {
                    manager.toggleTake()
                } label: {
                    Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .help(Text(manager.isRunning ? "Pause" : "Play"))

                Button {
                    panelManager.toggle()
                } label: {
                    Image(systemName: panelManager.isVisible
                          ? "rectangle.on.rectangle.slash"
                          : "macwindow.on.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help(Text(panelManager.isVisible ? "Hide the floating prompter" : "Show the floating prompter"))
            }

            Button {
                beginPaste()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help(Text("Paste a script from the clipboard"))
        }
    }

    /// Jump targets, mirroring the number keys the panel listens for.
    private func sectionRail(_ script: TeleprompterScript) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(script.sections.enumerated()), id: \.element.id) { index, section in
                    let isCurrent = index == manager.currentSectionIndex
                    Button {
                        manager.jumpToSection(index)
                    } label: {
                        HStack(spacing: 3) {
                            if index < 9 {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .opacity(0.7)
                            }
                            Text(section.title.isEmpty ? String(localized: "Opening") : section.title)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            if section.mustCover {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 7))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(isCurrent ? Color.accentColor.opacity(0.35) : .white.opacity(0.08))
                        )
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 22)
    }

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $pastedText)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxHeight: .infinity)

            HStack(spacing: 6) {
                Text("Markdown: `## !` marks a section to cover, `> key:` a phrase to land.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(String(localized: "Cancel")) {
                    isPasting = false
                    pastedText = ""
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)

                Button(String(localized: "Add script")) {
                    let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    manager.addScript(markdown: trimmed, name: "")
                    isPasting = false
                    pastedText = ""
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            Text("No script yet")
                .font(.system(size: 12, weight: .semibold))
            Text("Copy some text, then use the clipboard button above.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Pre-fills from the clipboard, since that is almost always the intent.
    private func beginPaste() {
        pastedText = NSPasteboard.general.string(forType: .string) ?? ""
        isPasting = true
    }
}
