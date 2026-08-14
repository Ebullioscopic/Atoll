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
import UniformTypeIdentifiers

/// Settings pane for the teleprompter.
///
/// Lives outside `SettingsView.swift` so the monolith does not grow; that file
/// only gains a tab case and one call site. `SettingsTab` is file-private there,
/// so the search-highlight id is passed in.
struct TeleprompterSettings: View {
    var highlightID: (String) -> String = { $0 }

    @ObservedObject private var manager = TeleprompterManager.shared

    @Default(.enableTeleprompterFeature) private var isEnabled
    @Default(.teleprompterDisplayMode) private var displayMode
    @Default(.teleprompterScrollMode) private var scrollMode
    @Default(.teleprompterFontSize) private var fontSize
    @Default(.teleprompterFontChoice) private var fontChoice
    @Default(.teleprompterCustomFontFamily) private var customFontFamily
    @Default(.teleprompterWordsPerMinute) private var wordsPerMinute
    @Default(.teleprompterOpacity) private var opacity
    @Default(.teleprompterMirrored) private var isMirrored
    @Default(.teleprompterLocaleIdentifier) private var localeIdentifier
    @Default(.teleprompterPlaylistEnabled) private var playlistEnabled

    @State private var isImporting = false
    @State private var importError: String?
    @State private var isImportingKeynote = false
    @State private var keynoteError: String?
    @State private var historyTakes: [TeleprompterTake] = []

    var body: some View {
        Form {
            generalSection
            if isEnabled {
                libarySection
                keynoteSection
                playlistSection
                readingSection
                appearanceSection
                historySection
                privacySection
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Defaults.Toggle(key: .enableTeleprompterFeature) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teleprompter")
                    Text("Read a script next to your camera, in a floating window that screen sharing cannot see.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Teleprompter"))

            if isEnabled {
                Picker(selection: $displayMode) {
                    ForEach(TeleprompterDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show it in")
                        Text("The floating window is the default: it is the only surface big enough to read from, and it does not widen the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Teleprompter")
        }
    }

    // MARK: - Library

    private var libarySection: some View {
        Section {
            if manager.scripts.isEmpty {
                Text("No scripts yet. Import a Markdown or text file, or paste one into the Prompter tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manager.scripts) { script in
                    LabeledContent {
                        HStack(spacing: 8) {
                            if manager.currentScriptID != script.id {
                                Button(String(localized: "Use")) {
                                    manager.selectScript(id: script.id)
                                }
                                .buttonStyle(.borderless)
                            }
                            Button(role: .destructive) {
                                manager.removeScript(id: script.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(script.name)
                                if manager.currentScriptID == script.id {
                                    Text("current")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.green.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(summary(for: script))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                isImporting = true
            } label: {
                Text("Import a script…")
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Scripts")
        } footer: {
            Text("Markdown gives you more: `## !` marks a section you mean to cover, `## Intro (1:30)` gives it a target, `> key: …` marks a phrase to land, and any other `>` line is a note you will see but never read aloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summary(for script: TeleprompterScript) -> String {
        let words = "\(script.wordCount) " + String(localized: "words")
        let duration = TeleprompterScriptTextView.durationText(
            script.estimatedDuration(wordsPerMinute: wordsPerMinute)
        )
        let sections = "\(script.sections.count) " + String(localized: "sections")
        return "\(words) · \(duration) · \(sections)"
    }

    // MARK: - Playlist

    private var playlistSection: some View {
        Section {
            Defaults.Toggle(key: .teleprompterPlaylistEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run scripts in order")
                    Text("When one script ends the next begins, without touching the Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if playlistEnabled {
                Defaults.Toggle(key: .teleprompterPlaylistLoops) {
                    Text("Start again after the last one")
                }

                let ordered = manager.playlistScripts
                if ordered.isEmpty {
                    Text("Nothing in the running order yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { position, script in
                        LabeledContent {
                            HStack(spacing: 8) {
                                Button {
                                    manager.movePlaylistEntry(script.id, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(position == 0)

                                Button {
                                    manager.movePlaylistEntry(script.id, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(position == ordered.count - 1)

                                Button {
                                    manager.toggleInPlaylist(script.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        } label: {
                            Text("\(position + 1). \(script.name)")
                        }
                    }
                }

                let candidates = manager.scripts.filter { !manager.isInPlaylist($0.id) }
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates) { script in
                            Button(script.name) { manager.toggleInPlaylist(script.id) }
                        }
                    } label: {
                        Text("Add a script to the order…")
                    }
                }
            }
        } header: {
            Text("Running order")
        }
    }

    // MARK: - Keynote

    @ViewBuilder
    private var keynoteSection: some View {
        if KeynoteBridge.isInstalled {
            Section {
                Button {
                    importKeynote()
                } label: {
                    Text("Import the open deck's presenter notes")
                }
                .disabled(isImportingKeynote)

                Defaults.Toggle(key: .teleprompterFollowKeynote) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow the slideshow")
                        Text("While a take is running, the prompter moves to the section for whichever slide Keynote is showing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!manager.isKeynoteScript)

                if !manager.isKeynoteScript {
                    Text("Import a deck first — following needs to know which section belongs to which slide.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = keynoteError ?? manager.keynoteError?.errorDescription {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Keynote")
                    Text("experimental")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("One section per slide, skipped slides left out. Notes are copied, never changed, and Atoll never opens Keynote by itself. Marked experimental because this has been built against Keynote's own scripting dictionary but not yet confirmed against a live slideshow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importKeynote() {
        isImportingKeynote = true
        keynoteError = nil
        Task {
            defer { isImportingKeynote = false }
            do {
                let script = try await manager.importKeynoteDeck()
                if !script.sections.contains(where: { !$0.paragraphs.isEmpty }) {
                    keynoteError = String(localized: "That deck has no presenter notes to read.")
                }
            } catch {
                keynoteError = (error as? KeynoteBridgeError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    // MARK: - Take history

    private var historySection: some View {
        Section {
            if let script = manager.currentScript {
                // Read once when the script changes, not on every render: each
                // read is a file read and a JSON decode, and a settings pane
                // re-renders for every slider tick in it.
                TeleprompterTakeHistoryView(
                    takes: historyTakes,
                    script: script,
                    onDelete: { take in
                        manager.deleteTake(take.id, from: script.id)
                        historyTakes = manager.takes(for: script.id)
                    }
                )
                .task(id: script.id) { historyTakes = manager.takes(for: script.id) }
                .onChange(of: manager.lastTake?.id) { _, _ in
                    historyTakes = manager.takes(for: script.id)
                }

                if !historyTakes.isEmpty {
                    Button(role: .destructive) {
                        manager.clearTakeHistory()
                        historyTakes = []
                    } label: {
                        Text("Clear this script's history")
                    }
                }
            } else {
                Text("Choose a script to see its takes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Takes")
        } footer: {
            Text("Kept on this Mac only: the last \(TeleprompterTakeStore.maxTakesPerScript) takes per script, and nothing older than 30 days. No audio is ever recorded or saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reading

    private var readingSection: some View {
        Section {
            Picker(selection: $scrollMode) {
                ForEach(TeleprompterScrollMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Text("Advance")
            }
            .onChange(of: scrollMode) { _, mode in
                guard mode == .voice else { return }
                // Permission is asked here, the moment the user opts in, so the
                // system prompts arrive with an obvious reason attached — never
                // at launch.
                Task { await manager.prepareVoiceFollowing() }
            }

            if scrollMode == .voice {
                if let reason = manager.voiceUnavailability {
                    Label(reason.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if manager.supportsOnDeviceVoiceFollowing {
                    Label(
                        String(localized: "Recognised entirely on this Mac — no audio leaves it, and none is ever saved."),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label(
                        String(localized: "This language has no on-device model installed, so voice following is unavailable. Add it in System Settings › Keyboard › Dictation."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            if scrollMode == .automatic {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent {
                        Text("\(Int(wordsPerMinute)) wpm")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } label: {
                        Text("Pace")
                    }
                    Slider(value: $wordsPerMinute, in: 80...220, step: 5)
                }
            }

            Picker(selection: $localeIdentifier) {
                Text("Follow the system").tag("")
                ForEach(Self.commonLocales, id: \.self) { identifier in
                    let name = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
                    // The badge is shown here, at the moment of choosing, rather
                    // than discovered ten seconds before a call.
                    let onDevice = TeleprompterSpeechFollower.supportsOnDeviceRecognition(
                        for: Locale(identifier: identifier)
                    )
                    Text(onDevice ? name : name + " " + String(localized: "(no on-device voice)"))
                        .tag(identifier)
                }
            } label: {
                Text("Script language")
            }
        } header: {
            Text("Reading")
        } footer: {
            Text("The language decides how words are compared and which voice model is used. It matters for Turkish in particular, where the same letter lowercases differently.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A short list rather than every locale: this is a picker in a settings
    /// pane, not a language browser.
    private static let commonLocales = [
        "en_US", "en_GB", "tr_TR", "de_DE", "fr_FR", "es_ES", "it_IT",
        "nl_NL", "pt_BR", "ru_RU", "ja_JP", "ko_KR", "zh_Hans"
    ]

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent {
                    Text("\(Int(fontSize)) pt").foregroundStyle(.secondary).monospacedDigit()
                } label: {
                    Text("Text size")
                }
                Slider(value: $fontSize, in: 14...64, step: 1)
            }

            Picker(selection: $fontChoice) {
                ForEach(TeleprompterFontChoice.allCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            } label: {
                Text("Typeface")
            }

            if fontChoice == .openDyslexic, !TeleprompterFontChoice.openDyslexic.isAvailable {
                // Atoll cannot ship the font: committing a binary is against the
                // project's rules and raises a licence question.
                Text("OpenDyslexic is not installed. Install it from opendyslexic.org and it will be used here; until then the high-legibility system face is used.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if fontChoice == .custom {
                Picker(selection: $customFontFamily) {
                    Text("Choose…").tag("")
                    ForEach(Self.availableFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                } label: {
                    Text("Font")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent {
                    Text("\(Int(opacity * 100))%").foregroundStyle(.secondary).monospacedDigit()
                } label: {
                    Text("Background opacity")
                }
                Slider(value: $opacity, in: 0.1...1.0, step: 0.05)
            }

            Defaults.Toggle(key: .teleprompterMirrored) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mirror the text")
                    Text("For reading off a beam-splitter rig.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Defaults.Toggle(key: .teleprompterRememberPerScript) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember this per script")
                    Text("Each script keeps the size, typeface, pace, opacity and mirroring you last used with it. Switch it off to keep one setup for everything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Appearance")
        }
    }

    private static var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Defaults.Toggle(key: .teleprompterHideFromScreenCapture) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide from screen sharing and recording")
                    Text("Zoom, Teams, Meet, QuickTime and other recorders will not see the prompter. It stays visible to a camera pointed at your screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Hide from screen sharing and recording"))
        } header: {
            Text("Privacy")
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                importError = String(localized: "That file could not be read as text.")
                return
            }
            let name = url.deletingPathExtension().lastPathComponent
            manager.addScript(markdown: text, name: name)
        }
    }
}
