import Foundation
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "PermissionDeny")

/// Cached metadata for an in-flight tool_use_id, written on PreToolUse and consumed by
/// downstream PermissionRequest / PostToolUse events.
///
/// This lets us (1) correlate PermissionRequest payloads back to the originating tool
/// invocation even when some providers strip fields on re-emit, (2) drain stale queue
/// entries when the agent moved on (PostToolUse arrives while a PermissionRequest for
/// the same id is still queued), and (3) dedupe duplicate PermissionRequest replays.
struct PreToolUseRecord {
    let sessionId: String
    let toolName: String?
    let toolDescription: String?
    let toolInput: [String: Any]?
    let receivedAt: Date
}

extension AppState {
    /// TTL for cached PreToolUse records. Generous — tool calls may block on user input
    /// or long-running subprocesses; pruning reclaims memory for aborted/abandoned ids.
    static let pendingToolUseTTL: TimeInterval = 900  // 15 minutes

    /// Cache a PreToolUse so later PermissionRequest / PostToolUse events carrying the
    /// same tool_use_id can be correlated back to the originating invocation.
    func cachePreToolUseIfApplicable(_ event: HookEvent) {
        guard EventNormalizer.normalize(event.eventName) == "PreToolUse" else { return }
        guard let toolUseId = event.toolUseId, !toolUseId.isEmpty else { return }

        pendingToolUses[toolUseId] = PreToolUseRecord(
            sessionId: event.sessionId ?? "default",
            toolName: event.toolName,
            toolDescription: event.toolDescription,
            toolInput: event.toolInput,
            receivedAt: Date()
        )
    }

    /// Drop cache entries for a completed tool invocation. If a PermissionRequest for the
    /// same id is still sitting in the queue (e.g. agent moved on after a local timeout),
    /// drain it with a deny so we don't hold the UI hostage to a dead waiter.
    func resolveToolUseIfCompleted(_ event: HookEvent) {
        let normalized = EventNormalizer.normalize(event.eventName)
        guard normalized == "PostToolUse"
                || normalized == "PostToolUseFailure"
                || normalized == "PermissionDenied"
        else { return }
        guard let toolUseId = event.toolUseId, !toolUseId.isEmpty else { return }

        pendingToolUses.removeValue(forKey: toolUseId)

        guard let staleIndex = permissionQueue.firstIndex(where: { $0.toolUseId == toolUseId })
        else { return }

        if shouldKeepQueuedPermissionForCompletedEvent(event, normalizedEventName: normalized) {
            return
        }

        let stale = permissionQueue.remove(at: staleIndex)
        log.notice("⚠️ permission deny reason=resolveToolUseIfCompleted session=\(stale.event.sessionId ?? "nil", privacy: .public) toolUseId=\(toolUseId, privacy: .public) tool=\(stale.event.toolName ?? "nil", privacy: .public) triggerEvent=\(normalized, privacy: .public)")
        let denyBody = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
        stale.continuation.resume(returning: Data(denyBody.utf8))

        // If the card we were showing was the drained one, advance to the next pending
        // request (or collapse if nothing is left).
        let wasHead = staleIndex == 0
        if wasHead {
            if permissionQueue.isEmpty {
                if case .approvalCard = surface {
                    surface = .collapsed
                }
            } else {
                showNextPending()
            }
        }
    }

    /// Resolve permission requests that can never be correlated by tool_use_id.
    ///
    /// resolveToolUseIfCompleted only drains a queued permission when a later event
    /// carries the SAME non-empty tool_use_id. But Claude Code's PermissionRequest (or
    /// its follow-up PostToolUse/Stop) sometimes carries NO tool_use_id at all — when
    /// that happens the parked continuation has nothing to match against, so approving
    /// in the terminal never dismisses the card (#216).
    ///
    /// When a follow-up activity event arrives for a session, treat any queued
    /// permission for that session whose tool_use_id is empty/nil as approved-in-terminal:
    /// resume with an allow and remove it. Requests that DO carry a tool_use_id are left
    /// alone — they still wait for proper correlation so parallel tool calls don't deny
    /// each other (#147).
    func resolveOrphanPermissionsOnActivity(_ event: HookEvent) {
        let normalized = EventNormalizer.normalize(event.eventName)
        // Only activity events that mean "the agent moved on" past the prompt. A new
        // PermissionRequest/Question is handled by their own enqueue paths, not here.
        let activityEvents: Set<String> = [
            "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "UserPromptSubmit"
        ]
        guard activityEvents.contains(normalized) else { return }

        let sessionId = event.sessionId ?? "default"
        guard permissionQueue.contains(where: {
            ($0.event.sessionId ?? "default") == sessionId && ($0.toolUseId?.isEmpty ?? true)
        }) else { return }

        let headWasOrphan = permissionQueue.first.map { head in
            (head.event.sessionId ?? "default") == sessionId && (head.toolUseId?.isEmpty ?? true)
        } ?? false

        let allowBody = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        permissionQueue.removeAll { item in
            guard (item.event.sessionId ?? "default") == sessionId,
                  item.toolUseId?.isEmpty ?? true
            else { return false }
            log.notice("✅ permission approve reason=resolveOrphanPermissionsOnActivity session=\(sessionId, privacy: .public) tool=\(item.event.toolName ?? "nil", privacy: .public) triggerEvent=\(normalized, privacy: .public)")
            item.continuation.resume(returning: Data(allowBody.utf8))
            return true
        }

        // If the card we were showing was a drained orphan, advance to the next pending
        // request (or collapse if nothing is left).
        if headWasOrphan {
            if permissionQueue.isEmpty {
                if case .approvalCard = surface {
                    surface = .collapsed
                }
            } else {
                showNextPending()
            }
        }
    }

    /// Remove stale cache entries. Called from the cleanup timer tick.
    func prunePendingToolUses(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-AppState.pendingToolUseTTL)
        pendingToolUses = pendingToolUses.filter { $0.value.receivedAt >= cutoff }
    }

    /// Try to merge this permission request into an existing queue entry for the same
    /// tool_use_id. Returns true when the new arrival was treated as a replay and its
    /// continuation has already been resolved (caller must not enqueue).
    ///
    /// Behavior: the newer continuation replaces the queued one in-place. The older
    /// continuation is denied so Claude's prior waiter doesn't hang; the queue slot and
    /// its position remain the same so the visible card doesn't reshuffle under the user.
    func mergeDuplicatePermissionRequest(_ request: PermissionRequest) -> Bool {
        guard let toolUseId = request.toolUseId, !toolUseId.isEmpty else { return false }
        guard let existingIndex = permissionQueue.firstIndex(where: { $0.toolUseId == toolUseId })
        else { return false }

        let existing = permissionQueue[existingIndex]
        // #169: a shared tool_use_id alone is not enough to call this a replay.
        // Claude Code can emit several *parallel* tool calls (e.g. reading 4
        // files at once); if they carry the same id but different inputs they are
        // distinct requests and each needs its own decision. Treat it as a replay
        // — deny the old waiter, keep the new one in place — only when the tool
        // inputs match. Otherwise let the new request enqueue on its own.
        let existingInput = existing.event.toolInput ?? [:]
        let newInput = request.event.toolInput ?? [:]
        guard NSDictionary(dictionary: existingInput).isEqual(to: NSDictionary(dictionary: newInput)) else {
            return false
        }
        log.notice("⚠️ permission deny reason=mergeDuplicatePermissionRequest session=\(existing.event.sessionId ?? "nil", privacy: .public) toolUseId=\(toolUseId, privacy: .public) tool=\(existing.event.toolName ?? "nil", privacy: .public)")
        let denyBody = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#
        existing.continuation.resume(returning: Data(denyBody.utf8))
        permissionQueue[existingIndex] = request
        return true
    }

    func shouldKeepQueuedPermissionForCompletedEvent(_ event: HookEvent, normalizedEventName: String) -> Bool {
        guard normalizedEventName != "PermissionDenied" else { return false }

        let source = SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String)
            ?? permissionQueue.first(where: { $0.toolUseId == event.toolUseId })
                .flatMap { SessionSnapshot.normalizedSupportedSource($0.event.rawJSON["_source"] as? String) }

        switch source {
        case "trae", "traecn", "traecli":
            return true
        default:
            return false
        }
    }

    /// Backfill tool metadata from the cached PreToolUse when the PermissionRequest
    /// payload is missing fields (observed with some third-party CLIs that re-emit
    /// permission events without replaying the tool input).
    func enrichPermissionRequestFromCache(sessionId: String, event: HookEvent) {
        guard let toolUseId = event.toolUseId, !toolUseId.isEmpty else { return }
        guard let record = pendingToolUses[toolUseId] else { return }

        if sessions[sessionId]?.currentTool == nil, let name = record.toolName {
            sessions[sessionId]?.currentTool = name
        }
        if sessions[sessionId]?.toolDescription == nil, let desc = record.toolDescription {
            sessions[sessionId]?.toolDescription = desc
        }
    }
}
