import ActivityKit
import Foundation

struct CodeIslandSessionActivityPreview: Codable, Hashable, Identifiable {
    var sessionId: String?
    var source: String
    var status: String
    var toolName: String?
    var workspaceName: String?
    var message: String?
    var updatedAt: Date

    var id: String {
        sessionId ?? "\(source)-\(workspaceName ?? "session")-\(updatedAt.timeIntervalSince1970)"
    }

    var statusLabel: String {
        switch status {
        case "processing": return L10n.t(zh: "处理", en: "Working")
        case "running": return L10n.t(zh: "运行", en: "Running")
        case "waitingApproval": return L10n.t(zh: "待批准", en: "Needs Approval")
        case "waitingQuestion": return L10n.t(zh: "待回答", en: "Needs Answer")
        default: return L10n.t(zh: "空闲", en: "Idle")
        }
    }

    var sourceLabel: String {
        source.isEmpty ? "CodeIsland" : source.uppercased()
    }
}

struct CodeIslandActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sequence: UInt64
        var source: String
        var status: String
        var toolName: String?
        var workspaceName: String?
        var message: String?
        var pendingAction: String?
        var questionText: String?
        var questionHeader: String?
        var questionProgress: String?
        var sessions: [CodeIslandSessionActivityPreview]
        var updatedAt: Date

        var statusLabel: String {
            switch status {
            case "processing": return L10n.t(zh: "处理中", en: "Processing")
            case "running": return L10n.t(zh: "运行中", en: "Running")
            case "waitingApproval": return L10n.t(zh: "待批准", en: "Needs Approval")
            case "waitingQuestion": return L10n.t(zh: "待回答", en: "Needs Answer")
            default: return L10n.t(zh: "空闲", en: "Idle")
            }
        }

        var sourceLabel: String {
            source.isEmpty ? "CodeIsland" : source.uppercased()
        }

        var compactStatusLabel: String {
            switch status {
            case "waitingApproval": return L10n.t(zh: "待批", en: "OK?")
            case "waitingQuestion": return L10n.t(zh: "待答", en: "Q?")
            case "processing": return L10n.t(zh: "处理", en: "Busy")
            case "running": return L10n.t(zh: "运行", en: "Run")
            default: return L10n.t(zh: "空闲", en: "Idle")
            }
        }

        var activeSessionCount: Int {
            sessions.filter { $0.status != "idle" }.count
        }
    }

    var sessionId: String?
}
