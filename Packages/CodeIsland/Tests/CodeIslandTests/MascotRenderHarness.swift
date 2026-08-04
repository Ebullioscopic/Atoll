import XCTest
import SwiftUI
@testable import CodeIsland

/// Offscreen render harness for mascot animation review (#15).
///
/// Not a pass/fail test of pixels — it renders each mascot's scenes at a
/// series of timeline instants into contact-sheet PNGs so animation changes
/// can be reviewed without launching the app. Sheets land in
/// `$MASCOT_SHEET_DIR` (skipped entirely when the variable is unset, so CI
/// never pays for it).
@MainActor
final class MascotRenderHarness: XCTestCase {

    /// One-frame icon export for cli-icons assets: renders each source's
    /// mascot at a fixed instant on a transparent background. Opt-in like the
    /// contact sheets (`MASCOT_ICON_DIR` + `MASCOT_ICON_SOURCES=kiro,openclaw`).
    func testRenderCliIcons() throws {
        guard let outDir = ProcessInfo.processInfo.environment["MASCOT_ICON_DIR"] else {
            throw XCTSkip("MASCOT_ICON_DIR not set — harness is opt-in")
        }
        let sources = (ProcessInfo.processInfo.environment["MASCOT_ICON_SOURCES"] ?? "kiro,openclaw")
            .split(separator: ",").map(String.init)
        let status: MascotAgentStatus = switch ProcessInfo.processInfo.environment["MASCOT_ICON_STATUS"] {
        case "idle": .idle
        case "waitingApproval": .waitingApproval
        case "waitingQuestion": .waitingQuestion
        default: .processing
        }
        let time = Double(ProcessInfo.processInfo.environment["MASCOT_ICON_TIME"] ?? "") ?? 0.0

        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        for source in sources {
            let icon = MascotIconFrame(source: source, status: status, time: time)
            let renderer = ImageRenderer(content: icon)
            renderer.scale = 2  // 64pt frame → 128px asset
            guard let cgImage = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
            else {
                XCTFail("icon render failed for \(source)"); continue
            }
            try png.write(to: URL(fileURLWithPath: "\(outDir)/\(source).png"))
        }
    }

    func testRenderContactSheets() throws {
        guard let outDir = ProcessInfo.processInfo.environment["MASCOT_SHEET_DIR"] else {
            throw XCTSkip("MASCOT_SHEET_DIR not set — harness is opt-in")
        }
        let sources = (ProcessInfo.processInfo.environment["MASCOT_SHEET_SOURCES"] ?? "claude,codex")
            .split(separator: ",").map(String.init)
        let statuses: [(String, MascotAgentStatus)] = [
            ("idle", .idle),
            ("processing", .processing),
            ("waitingApproval", .waitingApproval),
            ("waitingQuestion", .waitingQuestion),
        ]
        // Sample instants chosen to catch blink/quirk windows, not just phase 0.
        let times: [Double] = [0.0, 0.6, 1.3, 2.1, 2.9, 3.6, 4.4, 5.2, 6.1, 7.0, 7.8, 8.5]

        try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        for source in sources {
            for (label, status) in statuses {
                let sheet = MascotContactSheet(source: source, status: status, times: times)
                let renderer = ImageRenderer(content: sheet)
                renderer.scale = 4  // 4x for crisp pixel inspection
                guard let cgImage = renderer.cgImage else {
                    XCTFail("render failed for \(source)/\(label)"); continue
                }
                let rep = NSBitmapImageRep(cgImage: cgImage)
                guard let png = rep.representation(using: .png, properties: [:]) else {
                    XCTFail("png encode failed for \(source)/\(label)"); continue
                }
                let path = "\(outDir)/\(source)-\(label).png"
                try png.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}

/// Single transparent-background frame sized for a cli-icons asset.
private struct MascotIconFrame: View {
    let source: String
    let status: MascotAgentStatus
    let time: Double

    var body: some View {
        MascotContactSheet.routedMascot(source: source, status: status, size: 58)
            .environment(\.mascotAnimationsActive, false)
            .environment(\.mascotStaticTime, time)
            .frame(width: 64, height: 64)
    }
}

/// One row of frames for a (source, status) pair, each frame rendered at a
/// fixed timeline instant via the static-frame path of MascotTimeline
/// (mascotAnimationsActive=false renders content(mascotStaticTime) once).
private struct MascotContactSheet: View {
    let source: String
    let status: MascotAgentStatus
    let times: [Double]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(times, id: \.self) { t in
                VStack(spacing: 2) {
                    mascot
                        .environment(\.mascotAnimationsActive, false)
                        .environment(\.mascotStaticTime, t)
                        .frame(width: 64, height: 64)
                        .background(Color.black)
                    Text(String(format: "%.1f", t))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(6)
        .background(Color.black)
    }

    /// Direct routing (bypasses MascotView, which re-injects the live gate).
    private var mascot: some View {
        Self.routedMascot(source: source, status: status, size: 54)
    }

    @ViewBuilder
    static func routedMascot(source: String, status: MascotAgentStatus, size: CGFloat) -> some View {
        switch source {
        case "codex": DexView(status: status, size: size)
        case "gemini": GeminiView(status: status, size: size)
        case "cursor": CursorView(status: status, size: size)
        case "trae": TraeView(status: status, size: size)
        case "copilot": CopilotView(status: status, size: size)
        case "qoder": QoderView(status: status, size: size)
        case "droid": DroidView(status: status, size: size)
        case "codebuddy": BuddyView(status: status, size: size)
        case "stepfun": StepFunView(status: status, size: size)
        case "opencode": OpenCodeView(status: status, size: size)
        case "qwen": QwenView(status: status, size: size)
        case "antigravity": AntiGravityView(status: status, size: size)
        case "workbuddy": WorkBuddyView(status: status, size: size)
        case "hermes": HermesView(status: status, size: size)
        case "openclaw": OpenClawView(status: status, size: size)
        case "kiro": KiroView(status: status, size: size)
        case "kimi": KimiView(status: status, size: size)
        case "pi": PiView(status: status, size: size)
        case "cline": ClineView(status: status, size: size)
        default: ClawdView(status: status, size: size)
        }
    }
}
