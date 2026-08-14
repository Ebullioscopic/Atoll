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

/// What the user is being asked to approve.
enum AgentRequestDetail: Equatable, Sendable {
    case shellCommand(String)
    case fileEdit(path: String, preview: String?)
    case plan(String)
    case generic(String)

    /// The text a rule is keyed on, and what the classifier reads.
    var subject: String {
        switch self {
        case .shellCommand(let command): return command
        case .fileEdit(let path, _): return path
        case .plan(let text): return text
        case .generic(let text): return text
        }
    }
}

/// One agent hook blocked on a decision from the notch.
///
/// Not `Codable`: an agent's hook process dies when it stops waiting, so a
/// request cannot outlive Atoll in any useful way. The spool file it came from is
/// what survives a restart, and the request is rebuilt from that.
struct AgentPendingRequest: Identifiable, Equatable, Sendable {
    /// The spool request id — also the filename the blocked shim is watching.
    let id: String
    let sessionID: String
    let kind: AgentKind
    /// The event name exactly as the agent spelled it, so the reply echoes it back.
    let rawEventName: String
    let toolName: String?
    let detail: AgentRequestDetail
    let riskFlags: [CommandRiskFlag]
    let receivedAt: Date
    /// When Atoll will answer "no decision" on the user's behalf, slightly before
    /// the agent's own hook timeout so the shim always exits cleanly.
    let expiresAt: Date

    var risk: DestructiveRisk {
        DestructiveCommandClassifier.highestRisk(in: riskFlags)
    }

    /// Short label for the notch: `Bash`, `Edit`, or the event name.
    var toolLabel: String {
        if let toolName, !toolName.isEmpty { return toolName }
        return rawEventName
    }

    /// Whether a persistent "always allow" rule may be offered.
    ///
    /// Never for a high-risk command: a rule that silently approves
    /// `rm -rf` forever is the one outcome this feature must not enable.
    var allowsPersistentRule: Bool {
        risk < .high
    }
}
