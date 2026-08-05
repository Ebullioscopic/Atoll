import SwiftUI

/// Content-free animation states for Code Island's Codex mascot.
public enum CodeIslandMascotState: Equatable, Sendable {
    case idle
    case working
    case attention
    case success
    case failure
}

/// Dex, CodeIsland's pixel-cloud Codex mascot, extracted as a reusable view.
///
/// The view accepts no provider payload or session content. Atoll controls its
/// placement, lifetime, and whether it is visible in the notch.
public struct CodeIslandCodexMascotView: View {
    private let state: CodeIslandMascotState
    private let size: CGFloat
    private let animationSpeed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        state: CodeIslandMascotState,
        size: CGFloat = 30,
        animationSpeed: Double = 1
    ) {
        self.state = state
        self.size = size
        self.animationSpeed = min(max(animationSpeed, 0), 3)
    }

    public var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 0.05,
                paused: reduceMotion || animationSpeed == 0
            )
        ) { context in
            mascotFrame(
                time: context.date.timeIntervalSinceReferenceDate * animationSpeed
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func mascotFrame(time: TimeInterval) -> some View {
        let motion = reduceMotion ? 0 : motionOffset(time)
        let alertPulse = reduceMotion ? 0.55 : (sin(time * 5.5) + 1) / 2

        return ZStack {
            if state == .attention || state == .failure {
                Circle()
                    .fill(accentColor.opacity(0.08 + alertPulse * 0.09))
                    .frame(width: size * 0.9, height: size * 0.9)
            }

            Canvas { context, canvasSize in
                let unit = min(canvasSize.width / 16, canvasSize.height / 15)
                let originX = (canvasSize.width - 15 * unit) / 2
                let originY = (canvasSize.height - 13 * unit) / 2 + motion

                func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
                    Path(CGRect(
                        x: originX + x * unit,
                        y: originY + y * unit,
                        width: width * unit,
                        height: height * unit
                    ))
                }

                context.fill(
                    rectangle(3.5, 12.2, 8, 0.8),
                    with: .color(.black.opacity(0.3))
                )

                let cloudRows: [(CGFloat, CGFloat, CGFloat)] = [
                    (4, 1, 7), (3, 2, 9), (2, 3, 11),
                    (1, 4, 13), (1, 5, 13), (1, 6, 13),
                    (2, 7, 11), (2, 8, 11), (3, 9, 9), (4, 10, 7),
                ]
                for (x, y, width) in cloudRows {
                    context.fill(rectangle(x, y, width, 1), with: .color(cloudColor))
                }
                context.fill(rectangle(4, 0, 2, 1), with: .color(cloudColor))
                context.fill(rectangle(6.5, 0, 2, 1), with: .color(cloudColor))
                context.fill(rectangle(9, 0, 2, 1), with: .color(cloudColor))
                context.fill(rectangle(5, 10.5, 1, 1.5), with: .color(.gray))
                context.fill(rectangle(9, 10.5, 1, 1.5), with: .color(.gray))

                let promptColor = state == .attention || state == .failure
                    ? accentColor
                    : Color.black
                context.fill(rectangle(3.5, 5, 1, 1), with: .color(promptColor))
                context.fill(rectangle(4.5, 6, 1, 1), with: .color(promptColor))
                context.fill(rectangle(3.5, 7, 1, 1), with: .color(promptColor))
                context.fill(rectangle(6.5, 7, 3, 1), with: .color(promptColor))

                switch state {
                case .attention:
                    context.fill(rectangle(12.5, 1.5, 1.2, 3), with: .color(accentColor))
                    context.fill(rectangle(12.5, 5, 1.2, 1.2), with: .color(accentColor))
                case .success:
                    context.fill(rectangle(11.5, 4.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(12.5, 5.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(13.5, 3.5, 1, 2), with: .color(accentColor))
                case .failure:
                    context.fill(rectangle(11.5, 3.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(12.5, 4.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(13.5, 3.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(11.5, 5.5, 1, 1), with: .color(accentColor))
                    context.fill(rectangle(13.5, 5.5, 1, 1), with: .color(accentColor))
                case .idle, .working:
                    break
                }
            }
        }
    }

    private func motionOffset(_ time: TimeInterval) -> CGFloat {
        switch state {
        case .idle:
            return CGFloat(sin(time * 1.7)) * size * 0.025
        case .working:
            return CGFloat(abs(sin(time * 7.5))) * -size * 0.075
        case .attention:
            return CGFloat(sin(time * 18)) * size * 0.025
        case .success:
            return CGFloat(abs(sin(time * 4.5))) * -size * 0.045
        case .failure:
            return CGFloat(sin(time * 22)) * size * 0.035
        }
    }

    private var cloudColor: Color {
        Color(red: 0.92, green: 0.92, blue: 0.93)
    }

    private var accentColor: Color {
        switch state {
        case .attention: return .orange
        case .success: return .green
        case .failure: return .red
        case .idle, .working: return .white
        }
    }
}
