import SwiftUI

// MARK: - Mascot Animation Speed Environment

private struct MascotSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var mascotSpeed: Double {
        get { self[MascotSpeedKey.self] }
        set { self[MascotSpeedKey.self] = newValue }
    }
}

/// Routes a CLI source identifier to the correct pixel mascot view.
struct MascotView: View {
    let source: String
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @AppStorage(SettingsKey.mascotSpeed) private var speedPct = SettingsDefaults.mascotSpeed
    @ObservedObject private var animationGate = MascotAnimationGate.shared

    var body: some View {
        Group {
            switch source {
            case "codex":
                DexView(status: status, size: size)
            case "gemini", "google-antigravity":
                // Google Antigravity is Gemini-based — reuse the Gemini mascot.
                GeminiView(status: status, size: size)
            case "cursor", "cursor-cli":
                CursorView(status: status, size: size)
            case "trae", "traecn", "traecli":
                TraeView(status: status, size: size)
            case "copilot":
                CopilotView(status: status, size: size)
            case "qoder", "qoder-cli", "qoderwork":
                QoderView(status: status, size: size)
            case "droid":
                DroidView(status: status, size: size)
            case "codebuddy":
                BuddyView(status: status, size: size)
            case "codybuddycn":
                BuddyView(status: status, size: size)
            case "stepfun":
                StepFunView(status: status, size: size)
            case "opencode":
                OpenCodeView(status: status, size: size)
            case "qwen":
                QwenView(status: status, size: size)
            case "antigravity":
                AntiGravityView(status: status, size: size)
            case "workbuddy":
                WorkBuddyView(status: status, size: size)
            case "hermes":
                HermesView(status: status, size: size)
            case "openclaw":
                OpenClawView(status: status, size: size)
            case "kiro":
                KiroView(status: status, size: size)
            case "kimi":
                KimiView(status: status, size: size)
            case "pi", "omp":
                PiView(status: status, size: size)
            case "cline":
                ClineView(status: status, size: size)
            default:
                ClawdView(status: status, size: size)
            }
        }
        .environment(\.mascotSpeed, Double(speedPct) / 100.0)
        .environment(\.mascotAnimationsActive, animationGate.animationsActive)
        .environment(\.mascotAnimationEpoch, animationGate.epoch)
    }
}
