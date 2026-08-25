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

    /// The take just finished, shown as a debrief until dismissed.
    @Published private(set) var lastTake: TeleprompterTake?

    /// The running order across scripts.
    @Published private(set) var playlist = TeleprompterPlaylist()

    /// Why following a Keynote slideshow stopped, if it did.
    @Published private(set) var keynoteError: KeynoteBridgeError?
    /// The slide Keynote is showing, while it is showing one.
    @Published private(set) var currentSlideNumber: Int?

    private let store = TeleprompterLibraryStore()
    private let takeStore = TeleprompterTakeStore()
    private let playlistStore = TeleprompterPlaylistStore()
    private let speech = TeleprompterSpeechFollower()
    private let keynote = TeleprompterKeynoteFollower()
    /// When words were heard, relative to the take's start — the raw material for
    /// the pace and pause figures.
    private var speechTimestamps: [TimeInterval] = []
    private var followState = FollowState()
    private var followIndex: ScriptFollowIndex?
    /// `confirmedTokenIndex` at the moment the current take began. Automatic and
    /// manual modes never touch `followState.matchedWordCount`, so this is what
    /// tells `recordTakeIfWorthwhile` those modes made progress.
    private var takeStartTokenIndex: Int?
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
        playlist = playlistStore.load().sanitized(against: Set(scripts.map(\.id)))
        currentScriptID = scripts.first?.id
        applyPreferencesOfCurrentScript()

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

        // Appearance and pace are edited through the shared keys, wherever the
        // controls happen to live; whichever script is current adopts whatever
        // the reader settled on.
        for publisher in Self.perScriptPreferenceChanges() {
            publisher
                // Debounced because these keys are behind sliders. Capturing on
                // every step of a drag would rewrite the whole library — markdown
                // and tokens for every script — dozens of times, on the main
                // thread, for a value the user is still choosing.
                .debounce(for: .seconds(0.4), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.captureCurrentPreferences() }
                .store(in: &cancellables)
        }

        keynote.onSlideChange = { [weak self] slide in
            self?.handleKeynoteSlide(slide)
        }
        keynote.onFailure = { [weak self] reason in
            self?.keynoteError = reason
        }

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
        // Flush anything the debounce is still holding, so quitting mid-drag
        // does not lose the setting.
        captureCurrentPreferences()
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
        // Editing the words of an imported deck should not cost it its link to
        // the slides. Only carried over when the structure is unchanged; adding
        // a section makes the positional mapping a guess.
        if reparsed.sections.count == existing.sections.count {
            for position in reparsed.sections.indices {
                reparsed.sections[position].slideNumber = existing.sections[position].slideNumber
            }
        }
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
        // A script's takes are about that script; keeping them would leave an
        // orphaned record of what someone said out loud.
        takeStore.removeAll(for: id)
        scripts.removeAll { $0.id == id }
        setPlaylist(playlist.sanitized(against: Set(scripts.map(\.id))))
        if currentScriptID == id {
            currentScriptID = scripts.first?.id
            confirmedTokenIndex = 0
            endTake()
            applyPreferencesOfCurrentScript()
        }
        store.save(scripts)
    }

    func selectScript(id: UUID) {
        guard scripts.contains(where: { $0.id == id }) else { return }
        // Whatever the reader had just changed belongs to the script they are
        // leaving, and the debounced capture may not have fired yet.
        captureCurrentPreferences()
        // The follow index and follow state are built for the script being
        // left; carrying them across would match voice against the wrong
        // script's tokens. startListening() rebuilds both from scratch.
        let wasListening = isListening
        if wasListening {
            stopListening()
        }
        currentScriptID = id
        // Resume where this script was left, which is what makes reopening one
        // feel like returning to it. Clamped in case the script's tokens have
        // since changed and the saved position no longer exists.
        let savedIndex = currentScript?.preferences.lastTokenIndex ?? 0
        confirmedTokenIndex = min(max(savedIndex, 0), currentScript?.tokens.count ?? 0)
        applyPreferencesOfCurrentScript()
        if wasListening {
            startListening()
        }
    }

    // MARK: - Per-script memory

    /// The keys a script remembers for itself.
    private static func perScriptPreferenceChanges() -> [AnyPublisher<Void, Never>] {
        [
            Defaults.publisher(.teleprompterFontSize).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.teleprompterFontChoice).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.teleprompterWordsPerMinute).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.teleprompterOpacity).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.teleprompterMirrored).map { _ in () }.eraseToAnyPublisher()
        ]
    }

    /// Puts the current script's remembered setup back on screen.
    ///
    /// The views keep reading the shared keys, so there is exactly one rendering
    /// path; a script's memory is a set of values pushed into those keys when it
    /// becomes current, not a second source of truth the renderer has to consult.
    private func applyPreferencesOfCurrentScript() {
        guard Defaults[.teleprompterRememberPerScript], let script = currentScript else { return }
        let preferences = script.preferences
        Defaults[.teleprompterFontSize] = preferences.fontSize
        Defaults[.teleprompterFontChoice] = preferences.fontChoice
        Defaults[.teleprompterWordsPerMinute] = preferences.wordsPerMinute
        Defaults[.teleprompterOpacity] = preferences.opacity
        Defaults[.teleprompterMirrored] = preferences.isMirrored
    }

    /// Records the setup on the current script.
    ///
    /// Safe to run after ``applyPreferencesOfCurrentScript()``: the keys already
    /// hold that script's own values, so a late notification writes them back
    /// unchanged rather than starting a loop.
    private func captureCurrentPreferences() {
        guard Defaults[.teleprompterRememberPerScript],
              let id = currentScriptID,
              let index = scripts.firstIndex(where: { $0.id == id })
        else { return }

        var preferences = scripts[index].preferences
        preferences.fontSize = Defaults[.teleprompterFontSize]
        preferences.fontChoice = Defaults[.teleprompterFontChoice]
        preferences.wordsPerMinute = Defaults[.teleprompterWordsPerMinute]
        preferences.opacity = Defaults[.teleprompterOpacity]
        preferences.isMirrored = Defaults[.teleprompterMirrored]
        guard preferences != scripts[index].preferences else { return }

        scripts[index].preferences = preferences
        store.save(scripts)
    }

    // MARK: - Keynote

    /// Whether the current script knows which slide each section belongs to.
    var isKeynoteScript: Bool {
        currentScript?.sections.contains { $0.slideNumber != nil } ?? false
    }

    /// Imports the open deck's presenter notes as a script.
    @discardableResult
    func importKeynoteDeck() async throws -> TeleprompterScript {
        keynoteError = nil
        do {
            let deck = try await KeynoteBridge.readDeck()
            let script = addScript(
                markdown: KeynoteScriptBuilder.markdown(from: deck),
                name: deck.name
            )
            stampSlideNumbers(from: deck, onScriptWith: script.id)
            return currentScript ?? script
        } catch let error as KeynoteBridgeError {
            keynoteError = error
            throw error
        }
    }

    /// Records which slide each section came from.
    ///
    /// Positional, and safe to be: the builder emits exactly one heading per
    /// slide, and an imported note that begins with `#` is escaped rather than
    /// allowed to invent a section. If the counts ever disagree, nothing is
    /// stamped — a script that follows the wrong slides is worse than one that
    /// does not follow at all.
    private func stampSlideNumbers(from deck: KeynoteDeck, onScriptWith id: UUID) {
        guard let index = scripts.firstIndex(where: { $0.id == id }),
              scripts[index].sections.count == deck.slides.count
        else { return }

        for (position, slide) in deck.slides.enumerated() {
            scripts[index].sections[position].slideNumber = slide.number
        }
        store.save(scripts)
    }

    /// Moves to the section belonging to a slide.
    func jumpToSlide(_ number: Int) {
        guard let script = currentScript,
              let index = script.sections.firstIndex(where: { $0.slideNumber == number })
        else { return }
        jumpToSection(index)
    }

    private func handleKeynoteSlide(_ number: Int) {
        currentSlideNumber = number
        jumpToSlide(number)
    }

    private func startKeynoteIfNeeded() {
        guard Defaults[.teleprompterFollowKeynote], isKeynoteScript else { return }
        keynoteError = nil
        keynote.start()
    }

    private func stopKeynote() {
        keynote.stop()
        currentSlideNumber = nil
    }

    // MARK: - Playlist

    /// The script that follows the current one, if the running order says so.
    var nextInPlaylist: TeleprompterScript? {
        guard Defaults[.teleprompterPlaylistEnabled],
              let id = currentScriptID,
              let nextID = playlist.next(after: id, loops: Defaults[.teleprompterPlaylistLoops])
        else { return nil }
        return scripts.first { $0.id == nextID }
    }

    func isInPlaylist(_ id: UUID) -> Bool { playlist.contains(id) }

    func toggleInPlaylist(_ id: UUID) {
        var updated = playlist
        updated.contains(id) ? updated.remove(id) : updated.add(id)
        setPlaylist(updated)
    }

    func movePlaylistEntry(_ id: UUID, by offset: Int) {
        var updated = playlist
        updated.move(id, by: offset)
        setPlaylist(updated)
    }

    /// Scripts in reading order, for the playlist editor.
    var playlistScripts: [TeleprompterScript] {
        playlist.scriptIDs.compactMap { id in scripts.first { $0.id == id } }
    }

    private func setPlaylist(_ updated: TeleprompterPlaylist) {
        guard updated != playlist else { return }
        playlist = updated
        playlistStore.save(updated)
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

    /// Moves to the next section, or to the very end when there is none left.
    func jumpToNextSection() {
        guard let script = currentScript else { return }
        let next = currentSectionIndex + 1
        guard script.sections.indices.contains(next) else {
            setTokenIndex(script.tokens.count)
            return
        }
        jumpToSection(next)
    }

    /// Moves to the start of this section, or to the previous one when already
    /// there — the behaviour of a track-back button, which is what people expect
    /// from a key they press while talking.
    func jumpToPreviousSection() {
        guard let script = currentScript,
              script.sections.indices.contains(currentSectionIndex)
        else { return }
        let start = script.sections[currentSectionIndex].tokenRange.lowerBound
        if confirmedTokenIndex > start {
            setTokenIndex(start)
        } else {
            jumpToSection(currentSectionIndex - 1)
        }
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
        if let startedAt = takeStartedAt {
            speechTimestamps.append(Date().timeIntervalSince(startedAt))
        }
        // The matcher is the authority on position in this mode, and it only ever
        // moves the confirmed cursor forward.
        if followState.confirmedCursor != confirmedTokenIndex {
            confirmedTokenIndex = min(followState.confirmedCursor, script.tokens.count)
            persistPosition()

            // Reading the last word is the end of this script whether the pace
            // came from a clock or from a voice.
            if confirmedTokenIndex >= script.tokens.count, nextInPlaylist != nil {
                handleReachedEnd()
            }
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
        takeStartTokenIndex = confirmedTokenIndex
        speechTimestamps = []
        lastTake = nil
        // A second take must not inherit the first one's matched words and
        // covered sections. Voice mode rebuilds this when it starts listening;
        // the other modes never would.
        resetFollowState()
        startAdvanceIfNeeded()
    }

    private func resetFollowState() {
        followState = FollowState()
        followState.cursor = confirmedTokenIndex
        followState.confirmedCursor = confirmedTokenIndex
        followMode = .following
    }

    func pauseTake() {
        isRunning = false
        advanceTask?.cancel()
        advanceTask = nil
        stopListening()
        stopKeynote()
    }

    func resumeTake() {
        guard currentScript != nil else { return }
        isRunning = true
        if takeStartedAt == nil {
            takeStartedAt = Date()
            takeStartTokenIndex = confirmedTokenIndex
        }
        startAdvanceIfNeeded()
    }

    func endTake() {
        recordTakeIfWorthwhile()
        isRunning = false
        takeStartedAt = nil
        takeStartTokenIndex = nil
        advanceTask?.cancel()
        advanceTask = nil
        stopListening()
        stopKeynote()
        followMode = .following
        store.save(scripts)
    }

    /// What happens when the reader runs out of script.
    ///
    /// With a running order, the take rolls straight on to the next script — the
    /// point of a playlist is that nobody has to touch the Mac between parts. The
    /// finished part is still filed, but its debrief is not put on screen: the
    /// reader is mid-sentence in the next script and the debrief covers the text.
    private func handleReachedEnd() {
        guard let nextScript = nextInPlaylist else {
            pauseTake()
            return
        }

        recordTakeIfWorthwhile(surfacingDebrief: false)
        selectScript(id: nextScript.id)
        setTokenIndex(0)
        speechTimestamps = []
        takeStartedAt = Date()
        takeStartTokenIndex = confirmedTokenIndex
        resetFollowState()
        startAdvanceIfNeeded()
    }

    /// Files a debrief for a take that actually happened.
    ///
    /// A take with nothing matched is someone opening the prompter and closing
    /// it again; filing statistics for that would only clutter the history.
    private func recordTakeIfWorthwhile(surfacingDebrief: Bool = true) {
        // Voice mode registers progress as matched words; automatic and manual
        // modes never touch that counter and instead move the token cursor
        // directly, so either counts as a take worth filing.
        let madeProgress = followState.matchedWordCount > 0
            || (takeStartTokenIndex.map { confirmedTokenIndex > $0 } ?? false)
        guard let script = currentScript,
              let startedAt = takeStartedAt,
              madeProgress
        else { return }

        let take = TakeStatsBuilder.build(
            script: script,
            state: followState,
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            speechTimestamps: speechTimestamps,
            followedVoice: Defaults[.teleprompterScrollMode] == .voice,
            localeIdentifier: readingLocale.identifier
        )
        takeStore.append(take)
        if surfacingDebrief { lastTake = take }
    }

    /// Takes recorded for the current script, newest first.
    var takesForCurrentScript: [TeleprompterTake] {
        guard let id = currentScriptID else { return [] }
        return takeStore.takes(for: id)
    }

    func takes(for scriptID: UUID) -> [TeleprompterTake] {
        takeStore.takes(for: scriptID)
    }

    func deleteTake(_ takeID: UUID, from scriptID: UUID) {
        takeStore.remove(takeID: takeID, from: scriptID)
        if lastTake?.id == takeID { lastTake = nil }
        objectWillChange.send()
    }

    func dismissDebrief() {
        lastTake = nil
    }

    func clearTakeHistory() {
        guard let id = currentScriptID else { return }
        takeStore.removeAll(for: id)
        lastTake = nil
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
        // Independent of how words advance: Keynote moves the section, the
        // scroll mode moves the words inside it.
        startKeynoteIfNeeded()

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
                    self.handleReachedEnd()
                    return
                }
                self.confirmedTokenIndex += 1
            }
        }
    }
}
