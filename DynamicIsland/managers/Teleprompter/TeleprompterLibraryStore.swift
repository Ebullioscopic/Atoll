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

/// Where the teleprompter keeps its scripts.
///
/// Follows the repo convention of `Application Support/DynamicIsland/<Feature>/`.
enum TeleprompterStorage {
    /// Computed, and deliberately **not** creating anything.
    ///
    /// A lazily-created directory here would appear on every launch even with the
    /// feature switched off, which quietly breaks the promise that a disabled
    /// feature leaves no trace. Creation belongs to the write path.
    static var directory: URL {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return (support ?? fm.temporaryDirectory)
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("Teleprompter", isDirectory: true)
    }

    static var scriptsURL: URL {
        directory.appendingPathComponent("scripts.json")
    }

    /// Per-take history, written later by the debrief.
    static var takesDirectory: URL {
        directory.appendingPathComponent("takes", isDirectory: true)
    }

    /// The running order, kept beside the library rather than inside it so
    /// reordering does not rewrite every script's text.
    static var playlistURL: URL {
        directory.appendingPathComponent("playlist.json")
    }

    /// Called only when something is about to be written.
    @discardableResult
    static func ensureDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
    }
}

/// Loads and saves the script library.
///
/// Scripts live in a JSON file rather than `Defaults` because they are unbounded
/// in size — `UserDefaults` is deserialised on every launch, so a long script
/// there would tax startup forever.
///
/// Only the Markdown is authoritative. Sections and tokens are derived, and are
/// stored alongside purely so opening the library does not re-parse everything;
/// a version mismatch just re-derives them.
final class TeleprompterLibraryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = TeleprompterStorage.scriptsURL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [TeleprompterScript] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try decoder.decode([TeleprompterScript].self, from: data)
        } catch {
            // Move the unreadable file aside rather than let the next save()
            // silently overwrite it — an empty in-memory library plus a normal
            // save would otherwise delete scripts that just failed to decode.
            Logger.log("Teleprompter: could not decode the script library: \(error)", category: .ui)
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
    }

    func save(_ scripts: [TeleprompterScript]) {
        guard !scripts.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? encoder.encode(scripts) else {
            Logger.log("Teleprompter: could not encode the script library", category: .ui)
            return
        }
        TeleprompterStorage.ensureDirectory(fileURL.deletingLastPathComponent())
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Loads and saves the running order.
final class TeleprompterPlaylistStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL = TeleprompterStorage.playlistURL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted]
    }

    func load() -> TeleprompterPlaylist {
        guard let data = try? Data(contentsOf: fileURL),
              let playlist = try? decoder.decode(TeleprompterPlaylist.self, from: data)
        else { return TeleprompterPlaylist() }
        return playlist
    }

    func save(_ playlist: TeleprompterPlaylist) {
        guard !playlist.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? encoder.encode(playlist) else { return }
        TeleprompterStorage.ensureDirectory(fileURL.deletingLastPathComponent())
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Keeps a short history of takes, one file per script.
///
/// Bounded on both axes — the newest few per script, and nothing older than a
/// month — because this is a coaching aid, not an archive, and it holds a record
/// of what someone said out loud.
final class TeleprompterTakeStore {
    /// Takes kept per script.
    static let maxTakesPerScript = 20
    /// How long a take is kept regardless.
    static let retention: TimeInterval = 30 * 24 * 3600

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL = TeleprompterStorage.takesDirectory) {
        self.directory = directory
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private func fileURL(for scriptID: UUID) -> URL {
        directory.appendingPathComponent("\(scriptID.uuidString).json")
    }

    /// Takes for one script, newest first, with expired ones already dropped.
    func takes(for scriptID: UUID, now: Date = Date()) -> [TeleprompterTake] {
        guard let data = try? Data(contentsOf: fileURL(for: scriptID)),
              let stored = try? decoder.decode([TeleprompterTake].self, from: data)
        else { return [] }

        return stored
            .filter { now.timeIntervalSince($0.startedAt) <= Self.retention }
            .sorted { $0.startedAt > $1.startedAt }
    }

    @discardableResult
    func append(_ take: TeleprompterTake, now: Date = Date()) -> [TeleprompterTake] {
        var all = takes(for: take.scriptID, now: now)
        all.insert(take, at: 0)
        if all.count > Self.maxTakesPerScript {
            all.removeLast(all.count - Self.maxTakesPerScript)
        }
        write(all, for: take.scriptID)
        return all
    }

    func removeAll(for scriptID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: scriptID))
    }

    /// Drops one take. Someone reviewing a bad run should be able to throw it
    /// away without clearing the history they are comparing it against.
    @discardableResult
    func remove(takeID: UUID, from scriptID: UUID, now: Date = Date()) -> [TeleprompterTake] {
        let remaining = takes(for: scriptID, now: now).filter { $0.id != takeID }
        write(remaining, for: scriptID)
        return remaining
    }

    private func write(_ takes: [TeleprompterTake], for scriptID: UUID) {
        guard !takes.isEmpty else {
            removeAll(for: scriptID)
            return
        }
        guard let data = try? encoder.encode(takes) else { return }
        TeleprompterStorage.ensureDirectory(directory)
        try? data.write(to: fileURL(for: scriptID), options: .atomic)
    }
}
