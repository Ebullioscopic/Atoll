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
import Foundation

/// One slide's worth of what the presenter meant to say.
struct KeynoteSlide: Equatable, Sendable {
    let number: Int
    let notes: String
}

/// A deck as the prompter cares about it: a name and the notes, in order.
struct KeynoteDeck: Equatable, Sendable {
    let name: String
    let slides: [KeynoteSlide]

    var hasNotes: Bool { slides.contains { !$0.notes.isEmpty } }
}

enum KeynoteBridgeError: LocalizedError, Equatable {
    case notInstalled
    case notRunning
    case noDocument
    case notPermitted
    /// Keynote accepted the event and never answered.
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return String(localized: "Keynote is not installed.")
        case .notRunning:
            return String(localized: "Open your deck in Keynote first.")
        case .noDocument:
            return String(localized: "Keynote has no presentation open.")
        case .notPermitted:
            return String(localized: "Atoll needs permission to control Keynote. Allow it in System Settings › Privacy & Security › Automation.")
        case .timedOut:
            return String(localized: "Keynote did not answer. It is usually waiting on a dialog — bring it to the front, dismiss whatever it is showing, and try again.")
        case .failed(let reason):
            return reason
        }
    }
}

/// Reads presenter notes and the playing slide out of Keynote.
///
/// ## Never launches Keynote
/// Every entry point checks `NSWorkspace` first. `tell application` launches the
/// target as a side effect, so a stray poll would start Keynote on a Mac where
/// nobody is presenting — and Atoll polls this once a second during a take.
///
/// ## One round trip, then a pure parse
/// The deck comes back as a single delimited string rather than an AppleScript
/// list, so the interesting half — turning it into slides — is
/// ``KeynoteDeckParser``: pure, and testable without Keynote installed.
enum KeynoteBridge {
    static let bundleIdentifier = "com.apple.iWork.Keynote"

    /// Between fields of one slide.
    static let unitSeparator = "\u{001F}"
    /// Between slides.
    static let recordSeparator = "\u{001E}"

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// The whole deck's presenter notes, skipped slides excluded — they are not
    /// going to be shown, so their notes are not going to be said.
    static func readDeck() async throws -> KeynoteDeck {
        let raw = try await run("""
        set unitSep to (ASCII character 31)
        set recSep to (ASCII character 30)
        tell application id "\(bundleIdentifier)"
            if (count of documents) is 0 then return ""
            tell front document
                set out to (its name) & recSep
                repeat with s in slides
                    if not (skipped of s) then
                        set out to out & (slide number of s) & unitSep & (presenter notes of s as text) & recSep
                    end if
                end repeat
            end tell
            return out
        end tell
        """)

        guard let deck = KeynoteDeckParser.parse(raw) else { throw KeynoteBridgeError.noDocument }
        return deck
    }

    /// The slide on screen, or `nil` when no slideshow is playing.
    ///
    /// `playing` is asked first: outside a show `current slide` still answers —
    /// with whatever is selected in the editor — and following that would drag
    /// the prompter around while someone edits their deck.
    static func playingSlideNumber() async throws -> Int? {
        let raw = try await run("""
        tell application id "\(bundleIdentifier)"
            if not (playing) then return ""
            if (count of documents) is 0 then return ""
            return (slide number of (current slide of front document)) as text
        end tell
        """)
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func run(_ script: String) async throws -> String {
        guard isInstalled else { throw KeynoteBridgeError.notInstalled }
        guard isRunning else { throw KeynoteBridgeError.notRunning }

        do {
            let descriptor = try await AppleScriptHelper.execute(script)
            return descriptor?.stringValue ?? ""
        } catch {
            throw mapped(error)
        }
    }

    /// Automation refusal has its own answer, because the fix is a switch in
    /// System Settings rather than anything the user can do in Atoll.
    private static func mapped(_ error: Error) -> KeynoteBridgeError {
        let info = (error as NSError).userInfo
        let code = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        // -1743: user consent withheld. -600 / -609: the app went away between
        // the running check and the event. -1712: Keynote took the event and
        // never replied — observed on a Mac where it sat behind its own welcome
        // window, and worth its own message because nothing about it says
        // "Keynote is waiting for you".
        switch code {
        case -1743:
            return .notPermitted
        case -1712:
            return .timedOut
        case -600, -609:
            return .notRunning
        default:
            let message = (info[NSAppleScript.errorMessage] as? String)
                ?? error.localizedDescription
            return .failed(message)
        }
    }
}

/// Turns the bridge's delimited reply into a deck.
///
/// Pure and total: everything worth getting wrong about the import is decided
/// here, where a test can look at it.
enum KeynoteDeckParser {
    static func parse(_ raw: String) -> KeynoteDeck? {
        let records = raw.components(separatedBy: KeynoteBridge.recordSeparator)
        guard let name = records.first, !records.isEmpty else { return nil }
        // An empty reply means no document, which is not the same as a deck
        // with no slides.
        guard !raw.isEmpty else { return nil }

        let slides: [KeynoteSlide] = records.dropFirst().compactMap { record in
            guard !record.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let fields = record.components(separatedBy: KeynoteBridge.unitSeparator)
            guard fields.count >= 2, let number = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            let notes = fields.dropFirst().joined(separator: KeynoteBridge.unitSeparator)
            return KeynoteSlide(number: number, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return KeynoteDeck(
            name: trimmedName.isEmpty ? String(localized: "Keynote deck") : trimmedName,
            slides: slides
        )
    }
}

/// Writes a deck out as the Markdown the prompter reads.
enum KeynoteScriptBuilder {
    /// A section per slide, so following the show is a section jump.
    ///
    /// Slides with no notes still get a section: they are still slides you stand
    /// in front of, and dropping them would make the mapping from slide number
    /// to section a guess.
    static func markdown(from deck: KeynoteDeck) -> String {
        deck.slides.map { slide in
            let heading = "## " + String(
                format: String(localized: "Slide %lld"),
                slide.number
            )
            let body = slide.notes.isEmpty ? "" : "\n" + escaped(slide.notes)
            return heading + body
        }
        .joined(separator: "\n\n")
    }

    /// Escapes lines that would otherwise be read as prompter syntax.
    ///
    /// Presenter notes are prose written by someone who never agreed to this
    /// Markdown dialect. A note beginning `#` would invent a section and shift
    /// every slide after it; one beginning `>` would vanish into a speaker note
    /// and never be read aloud.
    static func escaped(_ notes: String) -> String {
        notes.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A code fence swallows every slide after it into one inert block,
            // and a bare rule line is dropped outright — both as silently as
            // the heading/blockquote cases below.
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            let isRule = trimmed.count >= 3
                && trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
            guard trimmed.hasPrefix("#") || trimmed.hasPrefix(">") || trimmed.hasPrefix("\\")
                    || isFence || isRule
            else { return line }
            return "\\" + trimmed
        }
        .joined(separator: "\n")
    }
}
