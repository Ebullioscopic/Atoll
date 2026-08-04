import Foundation
import CodeIslandCore

struct PermissionRequest {
    let event: HookEvent
    let continuation: CheckedContinuation<Data, Never>

    var toolUseId: String? { event.toolUseId }
}

struct AskUserQuestionItem {
    let payload: QuestionPayload
    let answerKey: String
    let multiSelect: Bool
}

struct AskUserQuestionState {
    let items: [AskUserQuestionItem]
    var answers: [String: String]

    var canConfirm: Bool {
        items.allSatisfy { answers[$0.answerKey] != nil }
    }

    mutating func select(questionIndex: Int, option: String) {
        guard items.indices.contains(questionIndex) else { return }
        answers[items[questionIndex].answerKey] = option
    }
}

/// How a queued question gets resolved once the user answers (or it is drained).
///
/// Hook-originated questions are answered by resuming a JSON `CheckedContinuation`
/// the bridge socket is awaiting. Codex app-server questions instead reach us as a
/// server->client JSON-RPC *request*, so they are answered by writing a JSON-RPC
/// *response* back over the running `codex app-server` client. The two paths are
/// mutually exclusive — exactly one is used per request.
enum QuestionResolution {
    /// Resume the awaiting hook bridge with the serialized hook response.
    case hook(CheckedContinuation<Data, Never>)
    /// Reply to a Codex app-server `item/tool/requestUserInput` request.
    /// `answersByKey` maps each question's answerKey to the chosen answer
    /// string(s); `nil` means the user skipped / the request was abandoned.
    case codexAppServer((_ answersByKey: [String: [String]]?) -> Void)

    /// Resume a hook continuation; no-op for app-server resolutions.
    func resumeHook(returning data: Data) {
        if case .hook(let continuation) = self {
            continuation.resume(returning: data)
        }
    }
}

struct QuestionRequest {
    let event: HookEvent
    let question: QuestionPayload
    let resolution: QuestionResolution
    /// true when converted from AskUserQuestion PermissionRequest
    let isFromPermission: Bool
    var askUserQuestionState: AskUserQuestionState?

    init(
        event: HookEvent,
        question: QuestionPayload,
        resolution: QuestionResolution,
        isFromPermission: Bool = false,
        askUserQuestionState: AskUserQuestionState? = nil
    ) {
        self.event = event
        self.question = askUserQuestionState?.items.first?.payload ?? question
        self.resolution = resolution
        self.isFromPermission = isFromPermission
        self.askUserQuestionState = askUserQuestionState
    }

    /// Back-compat convenience for hook-originated questions.
    init(
        event: HookEvent,
        question: QuestionPayload,
        continuation: CheckedContinuation<Data, Never>,
        isFromPermission: Bool = false,
        askUserQuestionState: AskUserQuestionState? = nil
    ) {
        self.init(
            event: event,
            question: question,
            resolution: .hook(continuation),
            isFromPermission: isFromPermission,
            askUserQuestionState: askUserQuestionState
        )
    }

    /// True when this question must be answered via the Codex app-server client
    /// rather than a hook continuation.
    var isCodexAppServer: Bool {
        if case .codexAppServer = resolution { return true }
        return false
    }

    /// Deliver answers to a Codex app-server question (no-op for hook questions).
    func resolveCodexAppServer(_ answersByKey: [String: [String]]?) {
        if case .codexAppServer(let reply) = resolution {
            reply(answersByKey)
        }
    }
}
