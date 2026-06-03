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

/// Represents a note fetched from Apple Notes via AppleScript
struct AppleNote: Identifiable, Hashable {
    let id: String // Apple Notes internal ID
    let title: String
    let content: String
    let modificationDate: Date
    let folderName: String
}

/// Manager that syncs notes from Apple Notes into Atoll's note store
class AppleNotesSyncManager: ObservableObject {
    static let shared = AppleNotesSyncManager()
    
    @Published var appleNotes: [AppleNote] = []
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastError: String?
    
    private init() {}
    
    /// Fetch notes from Apple Notes using AppleScript
    func fetchAppleNotes(limit: Int = 50) async {
        await MainActor.run { isSyncing = true; lastError = nil }
        
        let script = """
        tell application "Notes"
            set noteList to {}
            set noteCount to 0
            repeat with aNote in notes
                if noteCount ≥ \(limit) then exit repeat
                set noteTitle to name of aNote
                set noteBody to plaintext of aNote
                set noteMod to modification date of aNote
                set noteFolder to name of container of aNote
                set noteId to id of aNote
                set end of noteList to {noteId, noteTitle, noteBody, noteMod as string, noteFolder}
                set noteCount to noteCount + 1
            end repeat
            return noteList
        end tell
        """
        
        let result = await runAppleScript(script)

        // Fix #5: run fetchNotesIndividually off-main before hopping back to MainActor
        var parsed: [AppleNote] = []
        switch result {
        case .success(let output):
            if output.isEmpty {
                // Bulk script returned empty; fetch individually off-main
                parsed = await Task.detached { [weak self] () -> [AppleNote] in
                    self?.fetchNotesIndividually() ?? []
                }.value
            } else {
                // parseAppleScriptOutput itself calls fetchNotesIndividually synchronously;
                // run it off-main to keep the main thread free.
                parsed = await Task.detached { [weak self] () -> [AppleNote] in
                    guard let self else { return [] }
                    return self.parseAppleScriptOutput(output)
                }.value
            }
        case .failure:
            break
        }

        await MainActor.run {
            switch result {
            case .success:
                self.appleNotes = parsed
                self.lastSyncDate = Date()
            case .failure(let error):
                self.lastError = error.localizedDescription
            }
            self.isSyncing = false
        }
    }
    
    /// Import Apple Notes into Atoll's saved notes store
    func importToAtoll(notes: [AppleNote]) {
        var savedNotes = Defaults[.savedNotes]
        
        for appleNote in notes {
            // Skip if already imported (check by title + content match)
            let alreadyExists = savedNotes.contains { existing in
                existing.title == appleNote.title &&
                existing.content == appleNote.content
            }
            guard !alreadyExists else { continue }
            
            let noteItem = NoteItem(
                title: appleNote.title,
                content: appleNote.content,
                creationDate: appleNote.modificationDate,
                colorIndex: 1, // Blue to distinguish imported notes
                isPinned: false
            )
            savedNotes.insert(noteItem, at: 0)
        }
        
        Defaults[.savedNotes] = savedNotes
    }
    
    /// Import all fetched Apple Notes
    func importAllToAtoll() {
        importToAtoll(notes: appleNotes)
    }
    
    // MARK: - Private
    
    private func runAppleScript(_ source: String) async -> Result<String, Error> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: source)
                let output = appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(returning: .failure(NSError(domain: "AppleNotesSyncManager", code: -1, userInfo: [NSLocalizedDescriptionKey: message])))
                } else if let output = output {
                    continuation.resume(returning: .success(output.stringValue ?? ""))
                } else {
                    continuation.resume(returning: .success(""))
                }
            }
        }
    }
    
    private func parseAppleScriptOutput(_ output: String) -> [AppleNote] {
        // AppleScript returns nested lists as comma-separated values
        // Each note is: {id, title, body, modDate, folder}
        // We'll use a simpler per-note fetch approach if bulk parsing is unreliable
        
        guard !output.isEmpty else { return [] }
        
        // The output from AppleScript list-of-lists comes as a single string
        // We need to parse it carefully. Format varies but typically:
        // "id, title, body, date string, folder, id, title, body, date string, folder, ..."
        // Due to commas in content, we use a different strategy: fetch notes individually
        
        // For bulk fetch, we'll re-run with a delimiter-based approach
        return fetchNotesIndividually()
    }
    
    /// Fallback: fetch notes one at a time with clear delimiters
    private func fetchNotesIndividually() -> [AppleNote] {
        let countScript = """
        tell application "Notes"
            return count of notes
        end tell
        """
        
        var error: NSDictionary?
        let countResult = NSAppleScript(source: countScript)?.executeAndReturnError(&error)
        // Fix #6: check for AppleScript errors rather than silently proceeding
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            print("❌ [AppleNotesSyncManager] countScript error: \(msg)")
            return []
        }
        let count = min(Int(countResult?.int32Value ?? 0), 50)
        
        guard count > 0 else { return [] }
        
        var notes: [AppleNote] = []
        let delimiter = "|||ATOLL_DELIM|||"
        
        // Fetch in batch with delimiters
        let batchScript = """
        tell application "Notes"
            set output to ""
            set noteCount to 0
            repeat with aNote in notes
                if noteCount ≥ \(count) then exit repeat
                set output to output & (id of aNote) & "\(delimiter)" & (name of aNote) & "\(delimiter)" & (plaintext of aNote) & "\(delimiter)" & ((modification date of aNote) as string) & "\(delimiter)" & (name of container of aNote) & "\(delimiter)|||ATOLL_NOTE_END|||"
                set noteCount to noteCount + 1
            end repeat
            return output
        end tell
        """
        
        var batchError: NSDictionary?
        let batchResult = NSAppleScript(source: batchScript)?.executeAndReturnError(&batchError)
        // Fix #6: check for AppleScript batch errors rather than silently proceeding
        if let batchError = batchError {
            let msg = batchError[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            print("❌ [AppleNotesSyncManager] batchScript error: \(msg)")
            return []
        }
        
        guard let outputStr = batchResult?.stringValue, !outputStr.isEmpty else { return [] }
        
        let noteChunks = outputStr.components(separatedBy: "|||ATOLL_NOTE_END|||")
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .full
        
        for chunk in noteChunks {
            let parts = chunk.components(separatedBy: delimiter)
            guard parts.count >= 5 else { continue }
            
            let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let content = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let dateStr = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let folder = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
            
            let date = dateFormatter.date(from: dateStr) ?? Date()
            
            notes.append(AppleNote(
                id: id,
                title: title,
                content: content,
                modificationDate: date,
                folderName: folder
            ))
        }
        
        return notes
    }
}
