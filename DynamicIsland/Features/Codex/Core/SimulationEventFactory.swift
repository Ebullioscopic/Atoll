import Foundation

public enum CodexSimulationKind: String, Sendable {
    case running
    case waiting
    case completed
}

public enum SimulationEventFactory {
    public static func makeEnvelope(
        kind: CodexSimulationKind,
        sessionID: String = "simulated-session",
        turnID: String = "simulated-turn",
        cwd: String = "/tmp/codexatoll-demo",
        now: Date = Date()
    ) -> CodexHookEnvelope {
        let event: CodexHookEvent
        switch kind {
        case .running:
            event = CodexHookEvent(
                hookEventName: "UserPromptSubmit",
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                prompt: "模拟运行任务"
            )
        case .waiting:
            event = CodexHookEvent(
                hookEventName: "PermissionRequest",
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                toolName: "shell",
                toolInput: .object(["description": .string("模拟等待批准")])
            )
        case .completed:
            event = CodexHookEvent(
                hookEventName: "Stop",
                sessionID: sessionID,
                turnID: turnID,
                cwd: cwd,
                lastAssistantMessage: "模拟任务已完成"
            )
        }
        return CodexHookEnvelope(receivedAt: now, payload: event)
    }
}
