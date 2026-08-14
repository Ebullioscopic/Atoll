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
        return (try? decoder.decode([TeleprompterScript].self, from: data)) ?? []
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
