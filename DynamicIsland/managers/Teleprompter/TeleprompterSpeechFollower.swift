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

import AVFoundation
import Combine
import Foundation
import Speech

/// Why voice following is unavailable.
enum SpeechFollowUnavailability: Equatable, Sendable {
    case speechPermissionDenied
    case microphonePermissionDenied
    case noOnDeviceModel(languageName: String)
    case recogniserUnavailable
    case microphoneBusy(owner: String)
    case noInputDevice
    case failed(String)

    var message: String {
        switch self {
        case .speechPermissionDenied:
            return String(localized: "Atoll needs permission to use speech recognition. Enable it in System Settings › Privacy & Security › Speech Recognition.")
        case .microphonePermissionDenied:
            return String(localized: "Atoll needs microphone access. Enable it in System Settings › Privacy & Security › Microphone.")
        case .noOnDeviceModel(let languageName):
            return String(
                format: String(localized: "On-device speech isn't installed for %@. Add it in System Settings › Keyboard › Dictation, or pick another language."),
                languageName
            )
        case .recogniserUnavailable:
            return String(localized: "Speech recognition is unavailable right now.")
        case .microphoneBusy(let owner):
            return String(
                format: String(localized: "Atoll is already using the microphone for %@."),
                owner
            )
        case .noInputDevice:
            return String(localized: "No microphone is available.")
        case .failed(let reason):
            return reason
        }
    }
}

/// Listens and reports which words were said, so the prompter can follow along.
///
/// ## On-device only, without exception
/// `requiresOnDeviceRecognition` stays `true`. "Nothing leaves your Mac" is the
/// reason someone would put a prompter on their screen during a client call, so
/// it is a requirement rather than a preference — if a language has no on-device
/// model, the feature declines instead of quietly sending audio to a server.
///
/// ## Surviving the recognition task limit
/// A task ends after roughly a minute of audio. That would be fatal if position
/// lived in the transcript — but it lives in ``FollowState``, which is an index
/// into the *script*. Each task produces its own transcript starting from empty,
/// and only its incremental new words are forwarded, so a task boundary resets
/// nothing. Rotation prefers a silence so the cut costs no words at all, and is
/// forced before the framework would end the task itself.
@MainActor
final class TeleprompterSpeechFollower: ObservableObject {
    /// Words heard, already normalised for the matcher.
    var onWords: (([String]) -> Void)?
    /// Raised when listening stops for a reason the user should see.
    var onUnavailable: ((SpeechFollowUnavailability) -> Void)?

    @Published private(set) var isListening = false

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    private var locale: Locale = .current
    /// Guards against a result from a task that has already been retired.
    private var epoch = 0
    private var segmentWords: [String] = []
    private var segmentStartedAt = Date()
    private var rotationTimer: Timer?
    private var configurationObserver: NSObjectProtocol?

    /// Eligible to rotate at the first convenient moment.
    private static let softRotation: TimeInterval = 45
    /// Rotate regardless — comfortably before the framework ends the task itself.
    private static let hardRotation: TimeInterval = 55

    // MARK: - Availability

    /// Whether a language can be followed entirely on this Mac.
    static func supportsOnDeviceRecognition(for locale: Locale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    /// Languages the system can recognise, sorted for display.
    static func availableLocales() -> [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted {
                let lhs = Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
                let rhs = Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier
                return lhs < rhs
            }
    }

    /// Asks for both permissions, in the order the user will see them.
    ///
    /// Never called at launch — only when voice following is first switched on,
    /// so the prompts arrive with an obvious reason attached.
    static func requestAuthorization() async -> SpeechFollowUnavailability? {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return .speechPermissionDenied }

        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else { return .microphonePermissionDenied }

        return nil
    }

    // MARK: - Lifecycle

    /// Starts listening, or reports why it cannot.
    @discardableResult
    func start(locale: Locale) -> SpeechFollowUnavailability? {
        guard !isListening else { return nil }
        self.locale = locale

        if let blocker = MicrophoneLease.shared.blocker(for: .teleprompter) {
            return fail(.microphoneBusy(owner: blocker.displayName))
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return fail(.speechPermissionDenied)
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            return fail(.microphonePermissionDenied)
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return fail(.recogniserUnavailable)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return fail(.noOnDeviceModel(languageName: name))
        }
        guard MicrophoneLease.shared.acquire(.teleprompter) else {
            return fail(.microphoneBusy(owner: String(localized: "another feature")))
        }

        recognizer.defaultTaskHint = .dictation
        self.recognizer = recognizer

        do {
            try startAudio()
        } catch {
            MicrophoneLease.shared.release(.teleprompter)
            return fail(.failed(error.localizedDescription))
        }

        startTask()
        observeConfigurationChanges()
        isListening = true
        return nil
    }

    func stop() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }

        endTask()
        if engine.isRunning {
            engine.stop()
        }
        // Unconditional: a tap can be installed by startAudio() even when
        // engine.start() then fails, and engine is reused across starts.
        engine.inputNode.removeTap(onBus: 0)
        recognizer = nil
        MicrophoneLease.shared.release(.teleprompter)
        isListening = false
    }

    // MARK: - Audio

    private func startAudio() throws {
        let input = engine.inputNode
        // The node's own format, never a fabricated one: a mismatch here is the
        // classic cause of an immediate crash in `installTap`.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "Teleprompter", code: 1,
                userInfo: [NSLocalizedDescriptionKey: SpeechFollowUnavailability.noInputDevice.message]
            )
        }

        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // engine is a stored property reused by every start(locale:) call.
            // Leaving the tap on bus 0 makes the next installTap(onBus:) raise
            // an Objective-C exception and terminate the app.
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// The default input can change mid-take — a headset connects, a dock is
    /// unplugged — and the tap's format goes stale with it.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartAudio() }
        }
    }

    private func restartAudio() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        do {
            try startAudio()
            // The sample rate may have changed under the recogniser, so the task
            // is rotated rather than fed audio it did not start with.
            rotateTask()
        } catch {
            stop()
            onUnavailable?(.failed(error.localizedDescription))
        }
    }

    // MARK: - Recognition tasks

    private func startTask() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Non-negotiable: see the type's documentation.
        request.requiresOnDeviceRecognition = true
        // Punctuation is noise for word matching and only adds tokens to discard.
        request.addsPunctuation = false
        request.taskHint = .dictation

        self.request = request
        segmentWords = []
        segmentStartedAt = Date()

        let capturedEpoch = epoch
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error, epoch: capturedEpoch)
            }
        }

        scheduleRotation()
    }

    private func endTask() {
        epoch += 1
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        segmentWords = []
    }

    /// Starts a fresh task without losing the reader's place.
    ///
    /// Safe as a hard cut because position lives in the matcher, not here: at
    /// worst a word is lost at the seam, and the matcher absorbs that as an
    /// ordinary skip.
    private func rotateTask() {
        guard isListening else { return }
        endTask()
        startTask()
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.considerRotation() }
        }
    }

    private func considerRotation() {
        guard isListening else { return }
        let age = Date().timeIntervalSince(segmentStartedAt)
        guard age >= Self.softRotation else { return }

        // Past the soft deadline, rotate at the first quiet moment — a cut during
        // silence costs nothing. Past the hard deadline, rotate anyway.
        let quiet = Date().timeIntervalSince(lastWordAt) > 0.6
        if age >= Self.hardRotation || quiet {
            rotateTask()
        }
    }

    private var lastWordAt = Date()

    // MARK: - Results

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, epoch capturedEpoch: Int) {
        // A result from a task that has already been retired.
        guard capturedEpoch == epoch else { return }

        if let result {
            let words = TeleprompterTokenizer.normalizedWords(
                in: result.bestTranscription.formattedString,
                locale: locale
            )
            let delta = SpeechTranscriptDiffer.delta(previous: segmentWords, current: words)
            segmentWords = words

            if !delta.newWords.isEmpty {
                lastWordAt = Date()
                onWords?(delta.newWords)
            }

            if result.isFinal {
                rotateTask()
                return
            }
        }

        guard let error else { return }

        // A task ending on its own is expected once a minute; only a genuine
        // failure while listening is worth surfacing.
        let nsError = error as NSError
        let isExpectedEnd = nsError.domain == "kAFAssistantErrorDomain"
            && [203, 216, 1_101, 301].contains(nsError.code)
        if isExpectedEnd {
            rotateTask()
            return
        }

        Logger.log("Teleprompter: recognition failed: \(error.localizedDescription)", category: .ui)
        stop()
        onUnavailable?(.failed(error.localizedDescription))
    }

    @discardableResult
    private func fail(_ reason: SpeechFollowUnavailability) -> SpeechFollowUnavailability {
        onUnavailable?(reason)
        return reason
    }
}
