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

/// Decides which Atoll feature is using the microphone.
///
/// CoreAudio would happily let the Screen Assistant's recorder and the
/// teleprompter's recogniser open the default input at the same time, so this is
/// not a crash risk — it is a correctness and honesty one. Two simultaneous
/// clients means the assistant silently records an entire presentation, and the
/// user sees two microphone indicators with no explanation.
///
/// Small on purpose: one owner at a time, and each side names the other when it
/// is refused, so the message says what to do rather than just failing.
///
/// Lock-guarded rather than actor-isolated: the Screen Assistant's recording
/// paths are not on the main actor, and an arbiter every audio client must be
/// able to consult should not impose an isolation domain on its callers.
final class MicrophoneLease: @unchecked Sendable {
    static let shared = MicrophoneLease()

    enum Owner: String, Equatable, Sendable {
        case screenAssistant
        case teleprompter

        var displayName: String {
            switch self {
            case .screenAssistant: return String(localized: "the AI assistant")
            case .teleprompter: return String(localized: "the teleprompter")
            }
        }
    }

    private let lock = NSLock()
    private var owner: Owner?

    var currentOwner: Owner? {
        lock.lock()
        defer { lock.unlock() }
        return owner
    }

    private init() {}

    /// Takes the microphone, or reports who already has it.
    ///
    /// Re-acquiring as the current owner succeeds, so a restart does not have to
    /// release first.
    @discardableResult
    func acquire(_ candidate: Owner) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard owner == nil || owner == candidate else { return false }
        owner = candidate
        return true
    }

    /// Releases the microphone. Ignored when the caller is not the owner, so a
    /// stale teardown cannot take it away from whoever holds it now.
    func release(_ candidate: Owner) {
        lock.lock()
        defer { lock.unlock() }
        guard owner == candidate else { return }
        owner = nil
    }

    /// Who to name in a refusal message.
    func blocker(for candidate: Owner) -> Owner? {
        lock.lock()
        defer { lock.unlock() }
        guard let owner, owner != candidate else { return nil }
        return owner
    }
}
