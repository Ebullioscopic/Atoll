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

/// A running order over several scripts, so a talk assembled from parts can be
/// read straight through.
///
/// ## Each script appears at most once
/// The order is a list of identities, and `next(after:)` is keyed by identity —
/// a script listed twice would have two different successors and no way to tell
/// which one is meant. Enforced on the way in rather than guessed at on the way
/// out.
///
/// Pure and total: the whole rollover decision is testable without a microphone.
struct TeleprompterPlaylist: Codable, Equatable, Sendable {
    private(set) var scriptIDs: [UUID]

    init(scriptIDs: [UUID] = []) {
        // Deduplicated here too, because this initialiser also decodes whatever
        // is on disk, which an earlier version or a hand edit may have doubled up.
        var seen = Set<UUID>()
        self.scriptIDs = scriptIDs.filter { seen.insert($0).inserted }
    }

    var isEmpty: Bool { scriptIDs.isEmpty }
    var count: Int { scriptIDs.count }

    func contains(_ id: UUID) -> Bool { scriptIDs.contains(id) }

    func position(of id: UUID) -> Int? { scriptIDs.firstIndex(of: id) }

    /// What to read after this one, or `nil` at the end of a non-looping list.
    ///
    /// A script that is not in the list has no successor: the reader is somewhere
    /// else entirely, and dropping them into the playlist would be a surprise.
    func next(after id: UUID, loops: Bool = false) -> UUID? {
        guard let index = position(of: id) else { return nil }
        let following = index + 1
        if following < scriptIDs.count { return scriptIDs[following] }
        guard loops, let first = scriptIDs.first, first != id else { return nil }
        return first
    }

    mutating func add(_ id: UUID) {
        guard !contains(id) else { return }
        scriptIDs.append(id)
    }

    mutating func remove(_ id: UUID) {
        scriptIDs.removeAll { $0 == id }
    }

    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = position(of: id) else { return }
        let target = index + offset
        guard scriptIDs.indices.contains(target) else { return }
        scriptIDs.remove(at: index)
        scriptIDs.insert(id, at: target)
    }

    /// Drops entries whose script no longer exists.
    ///
    /// Deleting a script leaves a hole here that nothing else would ever clean up,
    /// and a playlist that silently skips a missing entry is better than one that
    /// stalls on it.
    func sanitized(against existing: Set<UUID>) -> TeleprompterPlaylist {
        TeleprompterPlaylist(scriptIDs: scriptIDs.filter { existing.contains($0) })
    }
}
