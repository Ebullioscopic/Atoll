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
import Combine
import Defaults
import Foundation

/// Runs the teleprompter: the script library, the reading position, and the
/// take that is currently in progress.
///
/// This phase advances the script manually or at a fixed pace. Following the
/// reader's voice arrives in a later phase and will drive the same
/// `confirmedTokenIndex`, so nothing here has to change to accommodate it.
@MainActor
final class TeleprompterManager: ObservableObject {
    static let shared = TeleprompterManager()

    @Published private(set) var scripts: [TeleprompterScript] = []
    @Published private(set) var currentScriptID: UUID?
    /// How far the reader has got, as an index into the current script's tokens.
    /// The single source of truth for highlighting, wherever it is rendered.
    @Published private(set) var confirmedTokenIndex: Int = 0
    @Published private(set) var isRunning = false
    /// When the current take started, for the elapsed clock.
    @Published private(set) var takeStartedAt: Date?

    /// Non-nil while voice following is unavailable, so the UI can say why.
    @Published private(set) var voiceUnavailability: SpeechFollowUnavailability?
    @Published private(set) var isListening = false
    /// What the matcher currently believes about the reader.
    @Published private(set) var followMode: FollowMode = .following

    private let store = TeleprompterLibraryStore()
    private let speech = TeleprompterSpeechFollower()
    private var followState = FollowState()
    private var followIndex: ScriptFollowIndex?
    private var cancellables = Set<AnyCancellable>()
    private var advanceTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {}

    // MARK: - Derived state

    var currentScript: TeleprompterScript? {
        guard let currentScriptID else { return nil }
        return scripts.first { $0.id == currentScriptID }
    }

    /// Index of the section the reader is in.
    var currentSectionIndex: Int {
        guard let script = currentScript, !script.tokens.isEmpty else { return 0 }
        let index = min(confirmedTokenIndex, script.tokens.count - 1)
        return script.tokens[index].sectionIndex
    }

    /// 0...1 through the script.
    var progress: Double {
        guard let script = currentScript, script.tokens.count > 0 else { return 0 }
        return min(1, Double(confirmedTokenIndex) / Double(script.tokens.count))
    }

    var elapsed: TimeInterval {
        guard let takeStartedAt else { return 0 }
        return Date().timeIntervalSince(takeStartedAt)
    }

    /// Whether anything should be shown in the notch right now.
    var hasVisibleActivity: Bool {
        Defaults[.enableTeleprompterFeature] && isRunning
    }

    /// The locale the script is read in, following the system unless overridden.
    var readingLocale: Locale {
        let identifier = Defaults[.teleprompterLocaleIdentifier]
        return identifier.isEmpty ? Locale.current : Locale(identifier: identifier)
    }

    // MARK: - Lifecycle

    /// Called from `applicationDidFinishLaunching`.
    ///
    /// Not `init()`: wiring `Defaults.publisher` or another shared manager from a
    /// singleton's initialiser deadlocks app launch, and anything that waits in
    /// there can re-enter its own `swift_once`.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        scripts = store.load()
        currentScriptID = scripts.first?.id

        Defaults.publisher(.enableTeleprompterFeature)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                if !change.newValue { self?.endTake() }
            }
            .store(in: &cancellables)

        // Switching modes mid-take should take effect immediately rather than at
        // the next take.
        Defaults.publisher(.teleprompterScrollMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isRunning else { return }
                self.pauseTake()
                self.resumeTake()
            }
            .store(in: &cancellables)

        speech.onWords = { [weak self] words in
            self?.consume(words)
        }
        speech.onUnavailable = { [weak self] reason in
            guard let self else { return }
            self.voiceUnavailability = reason
            self.isListening = false
            // Falling back to manual keeps the prompter usable rather than
            // leaving the reader with a frozen screen and no explanation.
            Defaults[.teleprompterScrollMode] = .manual
        }
    }

    func shutdown() {
        endTake()
        store.save(scripts)
    }

    /// Sections the reader has covered so far in this take.
    var coveredSectionIndices: Set<Int> { followState.coveredSectionIndices }
    /// Key phrases credited so far, including ones said in other words.
    var creditedKeyPhraseIDs: Set<UUID> { followState.creditedKeyPhraseIDs }

    // MARK: - Library

    @discardableResult
    func addScript(markdown: String, name: String) -> TeleprompterScript {
        let script = TeleprompterScriptParser.parse(
            markdown: markdown,
            name: name.isEmpty ? Self.derivedName(from: markdown) : name,
            locale: readingLocale
        )
        scripts.insert(script, at: 0)
        currentScriptID = script.id
        confirmedTokenIndex = 0
        store.save(scripts)
        return script
    }

    /// Re-parses a script after an edit, keeping its identity and bumping the
    /// revision so a recorded take can tell whether it still refers to this text.
    func updateScript(id: UUID, markdown: String) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        let existing = scripts[index]
        var reparsed = TeleprompterScriptParser.parse(
            markdown: markdown,
            name: existing.name,
            locale: readingLocale
        )
        reparsed.id = existing.id
        reparsed.createdAt = existing.createdAt
        reparsed.updatedAt = Date()
        reparsed.revision = existing.revision + 1
        reparsed.preferences = existing.preferences
        scripts[index] = reparsed

        if currentScriptID == id {
            confirmedTokenIndex = min(confirmedTokenIndex, max(0, reparsed.tokens.count - 1))
        }
        store.save(scripts)
    }

    func renameScript(id: UUID, to name: String) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].name = name
        scripts[index].updatedAt = Date()
        store.save(scripts)
    }

    func removeScript(id: UUID) {
        scripts.removeAll { $0.id == id }
        if currentScriptID == id {
            currentScriptID = scripts.first?.id
            confirmedTokenIndex = 0
            endTake()
        }
        store.save(scripts)
    }

    func selectScript(id: UUID) {
        guard scripts.contains(where: { $0.id == id }) else { return }
        currentScriptID = id
        // Resume where this script was left, which is what makes reopening one
        // feel like returning to it.
        confirmedTokenIndex = currentScript?.preferences.lastTokenIndex ?? 0
    }

    /// First heading, or first line, as a name for an imported script.
    static func derivedName(from markdown: String) -> String {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let heading = TeleprompterScriptParser.parseHeading(trimmed), !heading.title.isEmpty {
                return heading.title
            }
            return String(trimmed.prefix(60))
        }
        return String(localized: "Untitled script")
    }

    // MARK: - Reading position

    func setTokenIndex(_ index: Int) {
        guard let script = currentScript else { return }
        confirmedTokenIndex = max(0, min(index, script.tokens.count))
        // Moving by hand overrides the matcher: it must resume from where the
        // reader put the cursor, not from where it thought they were.
        followState.cursor = confirmedTokenIndex
        followState.confirmedCursor = confirmedTokenIndex
        followState.matchRun = 0
        followState.offScriptRun = 0
        followState.jumpTarget = nil
        followState.jumpConfirmations = 0
        persistPosition()
    }

    func advance(by delta: Int) {
        setTokenIndex(confirmedTokenIndex + delta)
    }

    /// Moves to the start of a section. Number keys 1-9 map onto this.
    func jumpToSection(_ sectionIndex: Int) {
        guard let script = currentScript,
              script.sections.indices.contains(sectionIndex)
        else { return }
        setTokenIndex(script.sections[sectionIndex].tokenRange.lowerBound)
    }

    func restart() {
        setTokenIndex(0)
    }

    private func persistPosition() {
        guard let id = currentScriptID,
              let index = scripts.firstIndex(where: { $0.id == id })
        else { return }
        scripts[index].preferences.lastTokenIndex = confirmedTokenIndex
        // Not saved on every keystroke; `shutdown()` and library edits flush it.
    }

    // MARK: - Voice following

    /// Begins listening, rebuilding the matcher's index for the current script.
    private func startListening() {
        guard let script = currentScript else { return }
        voiceUnavailability = nil

        followIndex = ScriptFollowIndex(script: script)
        followState = FollowState()
        followState.cursor = confirmedTokenIndex
        followState.confirmedCursor = confirmedTokenIndex

        if let reason = speech.start(locale: readingLocale) {
            voiceUnavailability = reason
            isListening = false
            Defaults[.teleprompterScrollMode] = .manual
            return
        }
        isListening = true
    }

    private func stopListening() {
        guard isListening else { return }
        speech.stop()
        isListening = false
    }

    /// Feeds heard words to the matcher and moves the prompter to where it says.
    private func consume(_ words: [String]) {
        guard let script = currentScript, let followIndex else { return }

        ScriptFollower.advance(
            state: &followState,
            spoken: words,
            script: script,
            index: followIndex,
            now: Date().timeIntervalSince1970
        )

        followMode = followState.mode
        // The matcher is the authority on position in this mode, and it only ever
        // moves the confirmed cursor forward.
        if followState.confirmedCursor != confirmedTokenIndex {
            confirmedTokenIndex = min(followState.confirmedCursor, script.tokens.count)
            persistPosition()
        }
    }

    /// Whether the chosen language can be followed entirely on this Mac.
    var supportsOnDeviceVoiceFollowing: Bool {
        TeleprompterSpeechFollower.supportsOnDeviceRecognition(for: readingLocale)
    }

    /// Asks for microphone and speech permission, then reports what blocks voice
    /// following, if anything.
    func prepareVoiceFollowing() async -> SpeechFollowUnavailability? {
        if let denied = await TeleprompterSpeechFollower.requestAuthorization() {
            voiceUnavailability = denied
            return denied
        }
        guard supportsOnDeviceVoiceFollowing else {
            let name = Locale.current.localizedString(forIdentifier: readingLocale.identifier)
                ?? readingLocale.identifier
            let reason = SpeechFollowUnavailability.noOnDeviceModel(languageName: name)
            voiceUnavailability = reason
            return reason
        }
        voiceUnavailability = nil
        return nil
    }

    // MARK: - Takes

    func startTake() {
        guard currentScript != nil else { return }
        isRunning = true
        takeStartedAt = Date()
        startAdvanceIfNeeded()
    }

    func pauseTake() {
        isRunning = false
        advanceTask?.cancel()
        advanceTask = nil
        stopListening()
    }

    func resumeTake() {
        guard currentScript != nil else { return }
        isRunning = true
        if takeStartedAt == nil { takeStartedAt = Date() }
        startAdvanceIfNeeded()
    }

    func endTake() {
        isRunning = false
        takeStartedAt = nil
        advanceTask?.cancel()
        advanceTask = nil
        stopListening()
        followMode = .following
        store.save(scripts)
    }

    func toggleTake() {
        isRunning ? pauseTake() : (takeStartedAt == nil ? startTake() : resumeTake())
    }

    /// Advances one word at a time at the configured pace.
    ///
    /// A per-word tick rather than a smooth scroll because the position is a
    /// token index, which is what the voice follower will drive too — so both
    /// modes move the same state and the renderer needs no special case.
    /// Starts whichever advance mechanism the user chose.
    private func startAdvanceIfNeeded() {
        advanceTask?.cancel()
        advanceTask = nil
        stopListening()

        switch Defaults[.teleprompterScrollMode] {
        case .voice:
            startListening()
            return
        case .manual:
            return
        case .automatic:
            break
        }
        startAutomaticAdvance()
    }

    private func startAutomaticAdvance() {

        let wordsPerMinute = max(20, Defaults[.teleprompterWordsPerMinute])
        let interval = 60.0 / wordsPerMinute

        advanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                guard let self, self.isRunning else { return }
                guard let script = self.currentScript else { return }
                guard self.confirmedTokenIndex < script.tokens.count else {
                    self.pauseTake()
                    return
                }
                self.confirmedTokenIndex += 1
            }
        }
    }
}
