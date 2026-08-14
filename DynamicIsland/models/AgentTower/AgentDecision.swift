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

/// What the user decided about a blocked agent request.
enum AgentDecision: Equatable, Sendable {
    case allowOnce
    /// Allow, and stop asking for this exact command in this session.
    case allowForSession
    /// Allow, and stop asking for this exact command in this project from now on.
    case alwaysAllow
    case deny(reason: String?)
    /// Atoll declines to have an opinion. Encoded as zero bytes, which is
    /// byte-identical to every failure path in the shim, so the agent falls back
    /// to its own permission prompt.
    case noDecision

    var isAllow: Bool {
        switch self {
        case .allowOnce, .allowForSession, .alwaysAllow: return true
        case .deny, .noDecision: return false
        }
    }

    /// Whether this decision should be remembered as a rule.
    var createsRule: Bool {
        self == .allowForSession || self == .alwaysAllow
    }
}

/// Turns a decision into the bytes an agent reads as its hook's stdout.
///
/// Each CLI has its own reply shape, and getting one wrong must degrade to "no
/// decision" rather than to an accidental approval — so unknown agents return
/// zero bytes.
///
/// ## The invariant
/// `noDecision` encodes to **empty data**, which is exactly what the shim prints
/// on every failure path. An agent therefore cannot distinguish "Atoll declined
/// to answer" from "Atoll was not running", and in both cases its own prompt
/// stands. Never encode `noDecision` as an explicit `"ask"`: that would make
/// Atoll's silence depend on the agent honouring a field.
enum AgentDecisionEncoder {
    static func encode(_ decision: AgentDecision, for request: AgentPendingRequest) -> Data {
        guard let object = payload(for: decision, request: request) else { return Data() }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            // A failure to serialise must not become an approval.
            return Data()
        }
        return data
    }

    static func payload(for decision: AgentDecision, request: AgentPendingRequest) -> [String: Any]? {
        if case .noDecision = decision { return nil }

        switch request.kind {
        case .claudeCode, .codex, .geminiCLI, .qwenCode:
            return hookSpecificOutput(for: decision, request: request)
        case .cursor:
            // Cursor answers with a bare `permission` key rather than Claude's
            // nested shape. Unverified against a real install, which is why the
            // agent is marked experimental in Settings.
            return ["permission": decision.isAllow ? "allow" : "deny"]
        case .opencode:
            // Not configurable by Atoll; nothing should ever reach here.
            return nil
        }
    }

    private static func hookSpecificOutput(
        for decision: AgentDecision,
        request: AgentPendingRequest
    ) -> [String: Any] {
        let reason: String
        switch decision {
        case .allowOnce:
            reason = String(localized: "Approved in Atoll")
        case .allowForSession:
            reason = String(localized: "Approved in Atoll for this session")
        case .alwaysAllow:
            reason = String(localized: "Always allowed in Atoll")
        case .deny(let text):
            reason = (text?.isEmpty == false ? text! : String(localized: "Denied in Atoll"))
        case .noDecision:
            reason = ""
        }

        return [
            "hookSpecificOutput": [
                "hookEventName": request.rawEventName,
                "permissionDecision": decision.isAllow ? "allow" : "deny",
                "permissionDecisionReason": reason
            ]
        ]
    }
}
