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

import Foundation
import Defaults

#if canImport(AppKit)
import AppKit
#endif

enum AppleNotesSyncError: LocalizedError {
    case automationDenied
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return String(localized: "Allow Atoll to control Notes in System Settings → Privacy & Security → Automation.")
        case .scriptFailed(let message):
            return message
        }
    }
}

struct RemoteAppleNote: Sendable {
    let id: String
    let title: String
    let content: String
    let creationDate: Date
    let modificationDate: Date
    let atollId: UUID?
}

@MainActor
final class AppleNotesSyncManager: ObservableObject {
    static let shared = AppleNotesSyncManager()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private static let syncFolderName = "Atoll"
    private static let fieldSeparator = "\u{241F}"
    private static let recordSeparator = "\u{241E}"
    private static let atollTagPattern = #"<!--atoll:id=([0-9A-Fa-f-]{36})-->"#

    private var syncTask: Task<Void, Never>?

    private init() {}

    func requestSync(localNotes: [NoteItem]) {
        guard Defaults[.enableAppleNotesSync] else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.sync(localNotes: localNotes)
        }
    }

    @discardableResult
    func sync(localNotes: [NoteItem]) async -> [NoteItem]? {
        guard Defaults[.enableAppleNotesSync] else { return nil }
        guard !isSyncing else { return nil }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let remoteNotes = try await fetchRemoteNotes()
            var merged = try await merge(localNotes: localNotes, remoteNotes: remoteNotes)
            merged = try await pushUnlinkedLocalNotes(merged)
            Defaults[.appleNotesLastSyncDate] = Date()
            return merged
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func pushNote(_ note: NoteItem) async -> NoteItem? {
        guard Defaults[.enableAppleNotesSync] else { return nil }

        do {
            if let appleNotesId = note.appleNotesId {
                try await updateRemoteNote(id: appleNotesId, note: note)
                return note
            } else {
                let newId = try await createRemoteNote(note)
                var updated = note
                updated.appleNotesId = newId
                return updated
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func deleteRemoteNote(appleNotesId: String) async {
        guard Defaults[.enableAppleNotesSync] else { return }

        do {
            try await deleteRemoteNote(id: appleNotesId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Merge

    private func merge(localNotes: [NoteItem], remoteNotes: [RemoteAppleNote]) async throws -> [NoteItem] {
        var notes = localNotes
        // Apple Notes 可能回吐同 id 的重复条目（跨账户/重复抓取），uniqueKeysWithValues 遇重复会 fatalError。
        // 改用 uniquingKeysWith，冲突时保留修改时间更新的一条。
        var remoteById = Dictionary(
            remoteNotes.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in rhs.modificationDate > lhs.modificationDate ? rhs : lhs }
        )
        var linkedRemoteIds = Set<String>()

        for index in notes.indices {
            guard let appleNotesId = notes[index].appleNotesId,
                  let remote = remoteById[appleNotesId] else { continue }

            linkedRemoteIds.insert(appleNotesId)

            if remote.modificationDate > notes[index].modificationDate {
                applyRemote(remote, to: &notes[index])
            } else if notes[index].modificationDate > remote.modificationDate {
                try await updateRemoteNote(id: appleNotesId, note: notes[index])
            }
        }

        // 遍历去重后的 remoteById.values 而非原始 remoteNotes：否则同 id 的旧副本可能先被
        // 处理并占位，新副本被跳过，atollId 匹配与新笔记导入的结果就会依赖数组顺序。
        for remote in remoteById.values where !linkedRemoteIds.contains(remote.id) {
            if let atollId = remote.atollId,
               let index = notes.firstIndex(where: { $0.id == atollId }) {
                linkedRemoteIds.insert(remote.id)
                notes[index].appleNotesId = remote.id
                if remote.modificationDate > notes[index].modificationDate {
                    applyRemote(remote, to: &notes[index])
                }
                continue
            }

            let imported = NoteItem(
                title: sanitizedTitle(remote.title),
                content: remote.content,
                creationDate: remote.creationDate,
                modificationDate: remote.modificationDate,
                colorIndex: 0,
                appleNotesId: remote.id
            )
            notes.append(imported)
            linkedRemoteIds.insert(remote.id)
        }

        notes.removeAll { note in
            guard let appleNotesId = note.appleNotesId else { return false }
            return !linkedRemoteIds.contains(appleNotesId) && remoteById[appleNotesId] == nil
        }

        return notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.modificationDate > rhs.modificationDate
        }
    }

    private func pushUnlinkedLocalNotes(_ notes: [NoteItem]) async throws -> [NoteItem] {
        var updated = notes
        for index in updated.indices where updated[index].appleNotesId == nil {
            let newId = try await createRemoteNote(updated[index])
            updated[index].appleNotesId = newId
        }
        return updated
    }

    private func applyRemote(_ remote: RemoteAppleNote, to note: inout NoteItem) {
        note.title = sanitizedTitle(remote.title)
        note.content = remote.content
        note.creationDate = remote.creationDate
        note.modificationDate = remote.modificationDate
        note.appleNotesId = remote.id
    }

    private func sanitizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Note") : trimmed
    }

    // MARK: - AppleScript bridge

    private func fetchRemoteNotes() async throws -> [RemoteAppleNote] {
        let script = """
        set fieldSep to "\(Self.fieldSeparator)"
        set recordSep to "\(Self.recordSeparator)"
        tell application "Notes"
            set epoch to (current date)
            set hours of epoch to 0
            set minutes of epoch to 0
            set seconds of epoch to 0
            set year of epoch to 1970
            set month of epoch to January
            set day of epoch to 1
            set chunks to {}
            repeat with n in notes of default account
                if password protected of n is false then
                    set notePlain to plaintext of n
                    set notePlain to my sanitizeField(notePlain, fieldSep, recordSep)
                    set atollId to my extractAtollId(body of n)
                    set chunk to (id of n) & fieldSep & (name of n) & fieldSep & ((creation date of n) - epoch as string) & fieldSep & ((modification date of n) - epoch as string) & fieldSep & notePlain & fieldSep & atollId
                    set end of chunks to chunk
                end if
            end repeat
            set AppleScript's text item delimiters to recordSep
            return chunks as text
        end tell

        on sanitizeField(txt, fieldSep, recordSep)
            set AppleScript's text item delimiters to fieldSep
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            set txt to parts as text
            set AppleScript's text item delimiters to recordSep
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            return parts as text
        end sanitizeField

        on extractAtollId(noteBody)
            if noteBody does not contain "atoll:id=" then return ""
            set AppleScript's text item delimiters to "atoll:id="
            set tail to item 2 of (text items of noteBody)
            set AppleScript's text item delimiters to "-->"
            return item 1 of (text items of tail)
        end extractAtollId
        """

        let output = try await runScriptReturningString(script)
        return parseRemoteNotes(output)
    }

    private func parseRemoteNotes(_ payload: String) -> [RemoteAppleNote] {
        guard !payload.isEmpty else { return [] }

        return payload
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: Character(Self.fieldSeparator), maxSplits: 5, omittingEmptySubsequences: false)
                guard fields.count >= 5 else { return nil }

                let id = String(fields[0])
                let title = String(fields[1])
                guard let created = parseAppleScriptSeconds(String(fields[2])),
                      let modified = parseAppleScriptSeconds(String(fields[3])) else { return nil }

                let content = String(fields[4])
                let atollId = fields.count > 5
                    ? UUID(uuidString: String(fields[5]))
                    : extractAtollId(from: content)

                return RemoteAppleNote(
                    id: id,
                    title: title,
                    content: content,
                    creationDate: created,
                    modificationDate: modified,
                    atollId: atollId
                )
            }
    }

    private func parseAppleScriptSeconds(_ raw: String) -> Date? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "E+", with: "e")
        guard let seconds = Double(normalized) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func extractAtollId(from content: String) -> UUID? {
        guard let regex = try? NSRegularExpression(pattern: Self.atollTagPattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let idRange = Range(match.range(at: 1), in: content) else { return nil }
        return UUID(uuidString: String(content[idRange]))
    }

    private func createRemoteNote(_ note: NoteItem) async throws -> String {
        try await ensureSyncFolderExists()

        let title = appleScriptEscape(sanitizedTitle(note.title))
        let body = appleScriptEscape(htmlBody(for: note))

        let script = """
        tell application "Notes"
            set newNote to make new note at folder "\(Self.syncFolderName)" of default account with properties {name:"\(title)", body:"\(body)"}
            return id of newNote
        end tell
        """

        return try await runScriptReturningString(script)
    }

    private func updateRemoteNote(id: String, note: NoteItem) async throws {
        let title = appleScriptEscape(sanitizedTitle(note.title))
        let body = appleScriptEscape(htmlBody(for: note))
        let escapedId = appleScriptEscape(id)

        let script = """
        tell application "Notes"
            set targetNote to first note whose id is "\(escapedId)"
            set name of targetNote to "\(title)"
            set body of targetNote to "\(body)"
        end tell
        """

        try await runScriptVoid(script)
    }

    private func deleteRemoteNote(id: String) async throws {
        let escapedId = appleScriptEscape(id)
        let script = """
        tell application "Notes"
            set matches to every note whose id is "\(escapedId)"
            if (count of matches) > 0 then
                delete item 1 of matches
            end if
        end tell
        """
        try await runScriptVoid(script)
    }

    private func ensureSyncFolderExists() async throws {
        let script = """
        tell application "Notes"
            try
                set _folder to folder "\(Self.syncFolderName)" of default account
            on error
                make new folder at default account with properties {name:"\(Self.syncFolderName)"}
            end try
        end tell
        """
        try await runScriptVoid(script)
    }

    private func htmlBody(for note: NoteItem) -> String {
        let escaped = note.content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = escaped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                if line.isEmpty { return "<div><br></div>" }
                return "<div>\(line)</div>"
            }
            .joined()

        return html + "<!--atoll:id=\(note.id.uuidString)-->"
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private func runScriptReturningString(_ script: String) async throws -> String {
        let descriptor = try await executeScript(script)
        guard let value = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AppleNotesSyncError.scriptFailed(String(localized: "Notes returned an empty response."))
        }
        return value
    }

    private func runScriptVoid(_ script: String) async throws {
        _ = try await executeScript(script)
    }

    private func executeScript(_ script: String) async throws -> NSAppleEventDescriptor {
        do {
            guard let descriptor = try await AppleScriptHelper.execute(script) else {
                throw AppleNotesSyncError.scriptFailed(String(localized: "Notes script returned no result."))
            }
            return descriptor
        } catch let error as NSError {
            if error.domain == "AppleScriptError", (error.userInfo["NSAppleScriptErrorNumber"] as? Int) == -1743 {
                throw AppleNotesSyncError.automationDenied
            }
            let message = (error.userInfo["NSAppleScriptErrorMessage"] as? String) ?? error.localizedDescription
            throw AppleNotesSyncError.scriptFailed(message)
        }
    }
}
