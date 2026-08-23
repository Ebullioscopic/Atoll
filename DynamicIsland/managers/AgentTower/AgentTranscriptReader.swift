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

/// What a tail read of an agent transcript yields.
struct AgentTranscriptSnapshot: Equatable, Sendable {
    /// Context the last assistant turn was carrying.
    let contextTokens: Int
    /// Model identifier from that same turn.
    let model: String?
    /// The session title the agent chose for itself, if it records one.
    let title: String?
    let permissionMode: String?
}

/// Reads the tail of an agent's transcript to work out its context usage.
///
/// ## Why a tail read
/// A live transcript here measured **4.1 MB over 1151 lines** and only grows.
/// Only the last assistant turn matters, so the file is read backwards from the
/// end and never loaded whole.
///
/// ## Why this does not reuse `JSONLUsageParser`
/// That type streams forward from offset 0 to aggregate 5-hour and 7-day
/// windows; here the requirement is the opposite — the single most recent
/// record. Its private `streamLines` has also diverged between `origin/dev` and
/// the local integration branch, so widening its API would guarantee a conflict
/// on every future merge for no shared logic.
enum AgentTranscriptReader {
    /// How much of the file's end to read. Comfortably more than one assistant
    /// turn plus the trailing metadata lines, even with large tool results.
    static let defaultTailBytes = 512 * 1024

    /// Reads `path` and returns the newest usable state, or `nil` when the file
    /// has no assistant turn in the window read.
    ///
    /// Never throws: a transcript that has been rotated, truncated or is being
    /// written to mid-read simply yields `nil`.
    static func read(path: String, tailBytes: Int = defaultTailBytes) -> AgentTranscriptSnapshot? {
        guard !path.isEmpty,
              let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

        let requested = UInt64(max(0, tailBytes))
        let offset = size > requested ? size - requested : 0
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        return parseTail(data, startedMidFile: offset > 0)
    }

    /// Scans a tail buffer backwards for the newest values.
    ///
    /// Split out from the file handling so it can be unit-tested against fixtures
    /// without touching disk.
    static func parseTail(_ data: Data, startedMidFile: Bool) -> AgentTranscriptSnapshot? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

        // Reading from an arbitrary offset almost always lands mid-line; that
        // fragment is not valid JSON and would be discarded anyway, but dropping
        // it explicitly keeps the intent clear.
        if startedMidFile, !lines.isEmpty {
            lines.removeFirst()
        }

        var contextTokens: Int?
        var model: String?
        var title: String?
        var permissionMode: String?

        // Backwards: the newest line wins, and each field can stop looking once
        // it is filled.
        for slice in lines.reversed() {
            if contextTokens != nil, title != nil, permissionMode != nil { break }
            guard let object = try? JSONSerialization.jsonObject(with: Data(slice)),
                  let root = object as? [String: Any]
            else { continue }

            switch root["type"] as? String {
            case "assistant":
                guard contextTokens == nil else { continue }
                // Subagent turns carry their own separate context; counting one
                // would corrupt the parent session's ring.
                guard root["isSidechain"] as? Bool != true else { continue }
                guard let message = root["message"] as? [String: Any],
                      message["role"] as? String == "assistant",
                      let usage = message["usage"] as? [String: Any]
                else { continue }
                let tokens = self.contextTokens(from: usage)
                guard tokens > 0 else { continue }
                contextTokens = tokens
                model = message["model"] as? String

            case "ai-title":
                if title == nil {
                    title = (root["aiTitle"] as? String)?.nonEmpty
                }

            case "permission-mode":
                if permissionMode == nil {
                    permissionMode = (root["permissionMode"] as? String)?.nonEmpty
                }

            default:
                continue
            }
        }

        guard let contextTokens else { return nil }
        return AgentTranscriptSnapshot(
            contextTokens: contextTokens,
            model: model,
            title: title,
            permissionMode: permissionMode
        )
    }

    /// Context carried into a turn.
    ///
    /// Verified against a live transcript: `input 2 + cache_creation 558 +
    /// cache_read 511_471 = 512_031`.
    ///
    /// `output_tokens` is deliberately excluded — it belongs to the reply being
    /// produced, not to the context that was sent. Note `usage` also contains a
    /// `cache_creation` *dictionary* alongside `cache_creation_input_tokens`;
    /// only the scalar is a token count.
    static func contextTokens(from usage: [String: Any]) -> Int {
        int(usage["input_tokens"])
            + int(usage["cache_creation_input_tokens"])
            + int(usage["cache_read_input_tokens"])
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
