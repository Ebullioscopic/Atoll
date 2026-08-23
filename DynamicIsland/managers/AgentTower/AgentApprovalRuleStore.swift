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

import Defaults
import Foundation

/// Remembers approvals so the same request is not asked twice.
///
/// ## Safety properties this type is responsible for
/// - **A rule is only ever created by an explicit user click.** Nothing here
///   infers one from repetition.
/// - **A high-risk command can never be covered by a rule.** `match` refuses
///   before it looks at anything else, so even a rule created when a command was
///   judged safe cannot auto-approve it once the classifier disagrees.
/// - **Session rules are never persisted.** They belong to one agent process and
///   would be meaningless — and dangerous — after a relaunch.
final class AgentApprovalRuleStore {
    private var rules: [AgentApprovalRule] = []
    private let fileURL: URL

    /// How long a project-scoped rule lasts. Bounded so an approval given during
    /// one afternoon's work does not silently apply months later.
    static let projectRuleLifetime: TimeInterval = 7 * 24 * 3600

    init(fileURL: URL = AgentTowerStorage.rulesURL) {
        self.fileURL = fileURL
        rules = Self.load(from: fileURL)
    }

    /// Rules the user can review, newest first. Session rules are included so the
    /// list reflects what is actually in force.
    var allRules: [AgentApprovalRule] {
        rules.sorted { $0.createdAt > $1.createdAt }
    }

    /// The rule that covers a request, if any.
    ///
    /// - Parameter cwd: the session's working directory, needed for project scope.
    func match(_ request: AgentPendingRequest, cwd: String?, now: Date = Date()) -> AgentApprovalRule? {
        // Refused before anything else: no stored decision may stand in for a
        // human on a destructive command.
        guard request.risk < .high else { return nil }
        return rules.first { $0.matches(request, cwd: cwd, now: now) }
    }

    /// Records the rule implied by a decision. Does nothing for decisions that
    /// should not be remembered.
    @discardableResult
    func record(
        _ decision: AgentDecision,
        for request: AgentPendingRequest,
        cwd: String?,
        now: Date = Date()
    ) -> AgentApprovalRule? {
        guard decision.createsRule else { return nil }
        // Belt and braces: the UI hides the button, and this refuses anyway.
        guard request.allowsPersistentRule else { return nil }

        let scope: AgentApprovalRule.Scope
        var expiresAt: Date?
        switch decision {
        case .allowForSession:
            scope = .session(request.sessionID)
        case .alwaysAllow:
            guard let cwd, !cwd.isEmpty else { return nil }
            scope = .project(cwd)
            expiresAt = now.addingTimeInterval(Self.projectRuleLifetime)
        default:
            return nil
        }

        let rule = AgentApprovalRule(
            id: UUID(),
            scope: scope,
            kind: request.kind,
            toolName: request.toolName ?? "",
            fingerprint: AgentApprovalRule.fingerprint(for: request),
            displaySubject: String(request.detail.subject.prefix(300)),
            createdAt: now,
            expiresAt: expiresAt
        )

        // Replace rather than duplicate an equivalent rule.
        rules.removeAll { $0.scope == rule.scope && $0.fingerprint == rule.fingerprint && $0.kind == rule.kind }
        rules.append(rule)
        persist()
        return rule
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        rules.removeAll()
        persist()
    }

    /// Drops rules for a session that has ended, and anything expired.
    func prune(now: Date = Date(), liveSessionIDs: Set<String>) {
        let before = rules.count
        rules.removeAll { rule in
            if rule.isExpired(now: now) { return true }
            if case .session(let id) = rule.scope { return !liveSessionIDs.contains(id) }
            return false
        }
        if rules.count != before { persist() }
    }

    // MARK: - Persistence

    /// Only project rules reach disk. Session rules are deliberately dropped.
    private func persist() {
        let durable = rules.filter {
            if case .project = $0.scope { return true }
            return false
        }

        guard !durable.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(durable) else { return }

        // Written 0o600 from the moment it exists: `Data.write(to:options:
        // .atomic)` publishes a fresh inode, so a chmod afterwards would leave a
        // window where the file carries the umask's default permissions.
        let fm = FileManager.default
        let tempURL = fileURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        guard fm.createFile(atPath: tempURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            Logger.log("Agent Tower: failed to write approval rules to a temporary file", category: .agents)
            return
        }
        do {
            if fm.fileExists(atPath: fileURL.path) {
                _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            Logger.log("Agent Tower: failed to persist approval rules: \(error.localizedDescription)", category: .agents)
            try? fm.removeItem(at: tempURL)
        }
    }

    private static func load(from url: URL) -> [AgentApprovalRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let loaded = try? decoder.decode([AgentApprovalRule].self, from: data) else { return [] }
        // A session rule that somehow reached disk is discarded on load.
        return loaded.filter {
            if case .project = $0.scope { return true }
            return false
        }
    }
}
