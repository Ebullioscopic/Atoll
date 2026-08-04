import Foundation

extension CodeIslandActivityAttributes.ContentState {
    init(payload: CompanionStatePayload) {
        self.init(
            sequence: payload.sequence,
            source: payload.source,
            status: payload.status.rawValue,
            toolName: payload.toolName,
            workspaceName: payload.workspaceName,
            message: payload.messages.last?.text,
            pendingAction: payload.pendingAction?.rawValue,
            questionText: payload.question?.question,
            questionHeader: payload.question?.header,
            questionProgress: payload.question.flatMap { question in
                question.total > 1 ? "\(question.index)/\(question.total)" : nil
            },
            sessions: Self.sessionPreviews(from: payload),
            updatedAt: payload.updatedAt
        )
    }

    private static func sessionPreviews(from payload: CompanionStatePayload) -> [CodeIslandSessionActivityPreview] {
        let previews = payload.sessions
        if !previews.isEmpty {
            return previews.map {
                CodeIslandSessionActivityPreview(
                    sessionId: $0.sessionId,
                    source: $0.source,
                    status: $0.status.rawValue,
                    toolName: $0.toolName,
                    workspaceName: $0.workspaceName,
                    message: $0.message,
                    updatedAt: $0.updatedAt
                )
            }
        }

        return [
            CodeIslandSessionActivityPreview(
                sessionId: payload.sessionId,
                source: payload.source,
                status: payload.status.rawValue,
                toolName: payload.toolName,
                workspaceName: payload.workspaceName,
                message: payload.question?.question ?? payload.messages.last?.text,
                updatedAt: payload.updatedAt
            )
        ]
    }
}
