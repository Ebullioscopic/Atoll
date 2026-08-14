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

/// A remembered approval, so the same request is not asked twice.
///
/// ## Why matching is exact
/// Rules match on a canonical fingerprint, never on a prefix or a substring. A
/// prefix rule for `git push` would silently cover `git push --force`; a
/// substring rule for `npm test` would cover `npm test && rm -rf ~`. Exact
/// matching means a rule can only ever approve the command the user actually
/// looked at, at the cost of asking again when an argument changes — which is the
/// right trade for something that runs code.
struct AgentApprovalRule: Identifiable, Codable, Equatable, Sendable {
    enum Scope: Codable, Equatable, Sendable {
        /// Only for one agent session; dies with it and is never persisted.
        case session(String)
        /// For one project directory, persisted.
        case project(String)
    }

    let id: UUID
    var scope: Scope
    var kind: AgentKind
    var toolName: String
    /// Canonical form of what was approved. See ``fingerprint(for:)``.
    var fingerprint: String
    /// Kept only so the rules list in Settings is readable.
    var displaySubject: String
    var createdAt: Date
    /// Project rules expire so a stale approval cannot outlive its context.
    var expiresAt: Date?

    func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }

    /// Whether this rule covers a request.
    func matches(_ request: AgentPendingRequest, cwd: String?, now: Date) -> Bool {
        guard !isExpired(now: now) else { return false }
        guard kind == request.kind else { return false }
        guard toolName == (request.toolName ?? "") else { return false }
        guard fingerprint == Self.fingerprint(for: request) else { return false }

        switch scope {
        case .session(let sessionID):
            return sessionID == request.sessionID
        case .project(let path):
            guard let cwd, !cwd.isEmpty else { return false }
            return path == cwd
        }
    }

    /// Canonical key for a request.
    ///
    /// Whitespace runs are collapsed so re-indentation does not defeat a rule,
    /// but nothing else is normalised — in particular no case folding and no
    /// argument reordering, because both change what a command does.
    static func fingerprint(for request: AgentPendingRequest) -> String {
        let subject = request.detail.subject
        let collapsed = subject
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return "\(request.kind.rawValue)|\(request.toolName ?? "")|\(collapsed)"
    }
}
