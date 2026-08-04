import SwiftUI

/// OpenClaw mascot (#235) — a pixel space lobster, after OpenClaw's "Molty" 🦞.
/// Red-orange shell, two big claws, stalk eyes. Drawn with the shared V-mapper
/// pattern and driven by MascotTimeline (8fps idle / 20fps active).
struct OpenClawView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    private static let shellC = Color(red: 0.93, green: 0.36, blue: 0.24)
    private static let shellDark = Color(red: 0.72, green: 0.24, blue: 0.16)
    private static let clawC = Color(red: 0.98, green: 0.47, blue: 0.30)
    private static let eyeC = Color(red: 0.12, green: 0.10, blue: 0.16)
    private static let alertC = Color(red: 1.0, green: 0.62, blue: 0.2)

    @State private var alive = false

    var body: some View {
        Group {
            switch status {
            case .idle:                 sleepScene
            case .processing, .running: workScene
            case .waitingApproval, .waitingQuestion: alertScene
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: status) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { alive = true }
        }
    }

    // ── Coordinate helper (same convention as the other mascots) ──
    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat, y0: CGFloat
        init(_ sz: CGSize, svgW: CGFloat = 16, svgH: CGFloat = 14, svgY0: CGFloat = 3) {
            s = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

    /// Body + stalk eyes + claws. `clawL/R` raise the claws (negative = up),
    /// `eyeOpen` scales the pupils, `dy` floats the whole lobster.
    private func drawLobster(
        _ c: GraphicsContext, v: V, dy: CGFloat,
        clawL: CGFloat, clawR: CGFloat, eyeOpen: CGFloat, shadow: Bool = true
    ) {
        if shadow {
            c.fill(Path(v.r(4, 15, 8, 1)), with: .color(.black.opacity(0.3)))
        }
        // Tail fan behind
        c.fill(Path(v.r(6, 12.5, 4, 2, dy: dy)), with: .color(Self.shellDark))
        // Shell body
        c.fill(Path(v.r(4, 7, 8, 6, dy: dy)), with: .color(Self.shellC))
        c.fill(Path(v.r(5, 6, 6, 1, dy: dy)), with: .color(Self.shellC))
        // Shell segments
        c.fill(Path(v.r(4.5, 10.5, 7, 0.6, dy: dy)), with: .color(Self.shellDark.opacity(0.6)))
        // Stalk eyes
        c.fill(Path(v.r(6, 4.5, 1, 2, dy: dy)), with: .color(Self.shellC))
        c.fill(Path(v.r(9, 4.5, 1, 2, dy: dy)), with: .color(Self.shellC))
        let eyeH = max(0.3, 1.4 * eyeOpen)
        c.fill(Path(v.r(5.7, 4.2 + (1.4 - eyeH) / 2, 1.6, eyeH, dy: dy)), with: .color(Self.eyeC))
        c.fill(Path(v.r(8.7, 4.2 + (1.4 - eyeH) / 2, 1.6, eyeH, dy: dy)), with: .color(Self.eyeC))
        // Claws — pixel pincers, raised by clawL/R
        c.fill(Path(v.r(1.5, 8.5 + clawL, 2.5, 3, dy: dy)), with: .color(Self.clawC))
        c.fill(Path(v.r(1.5, 7.7 + clawL, 1.2, 1.2, dy: dy)), with: .color(Self.clawC))  // upper pincer tip
        c.fill(Path(v.r(12, 8.5 + clawR, 2.5, 3, dy: dy)), with: .color(Self.clawC))
        c.fill(Path(v.r(13.3, 7.7 + clawR, 1.2, 1.2, dy: dy)), with: .color(Self.clawC))
        // Little legs
        for x: CGFloat in [5, 7.5, 10] {
            c.fill(Path(v.r(x, 13, 1, 1.3, dy: dy)), with: .color(Self.shellDark))
        }
    }

    // ── SLEEP: drifting, claws drooped, slow-blink stalk eyes, Z's ──
    private var sleepScene: some View {
        ZStack {
            MascotTimeline(interval: 0.12) { t in
                let float = sin(t * 2 * .pi / 4.15) * 0.65 + sin(t * 2 * .pi / 6.6) * 0.35
                // A claw twitches in its dreams now and then.
                let twitch = MascotMotion.quirk(t, cycle: 7.5, duration: 0.6, seed: 0xC1A3)
                return Canvas { c, sz in
                    let v = V(sz)
                    drawLobster(
                        c, v: v, dy: float,
                        clawL: 1.0 - twitch * 0.8, clawR: 1.0,
                        eyeOpen: 0.15
                    )
                }
            }
            MascotTimeline(interval: 0.12) { t in
                floatingZs(t: t)
            }
        }
    }

    private func floatingZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let ci = Double(i)
                let cycle = 3.0 + ci * 0.4
                let p = max(0, ((t - ci * 1.1).truncatingRemainder(dividingBy: cycle)) / cycle)
                let fontSize: CGFloat = max(6, size * CGFloat(0.16 + p * 0.08))
                let opacity: Double = p < 0.8 ? 0.6 - ci * 0.15 : (1 - p) * 3 * 0.6
                let dx = size * CGFloat(0.12 + ci * 0.06)
                let dy = -size * CGFloat(0.12 + p * 0.34)
                Text("z")
                    .font(.system(size: fontSize, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .offset(x: dx, y: dy)
            }
        }
    }

    // ── WORK: claws snip-typing with humanized cadence ──
    private var workScene: some View {
        MascotTimeline(interval: 0.05) { t in
            let pause = MascotMotion.quirk(t, cycle: 10.5, duration: 1.2, seed: 0xC1A4)
            let intensity = 1.0 - pause
            let bounce = sin(t * 2 * .pi / 0.42) * 0.9 * intensity
            let strokeL = MascotMotion.typingStroke(t, cadence: 0.16, seed: 0xC1A5)
            let strokeR = MascotMotion.typingStroke(t, cadence: 0.13, seed: 0xC1A6)
            let clawL = (strokeL.active ? CGFloat(sin(t * 2 * .pi / 0.16)) : -0.5) * 0.9 * intensity
            let clawR = (strokeR.active ? CGFloat(sin(t * 2 * .pi / 0.13)) : -0.5) * 0.9 * intensity
            let blink = MascotMotion.blink(t, seed: 0xC1A7)
            return Canvas { c, sz in
                let v = V(sz)
                drawLobster(c, v: v, dy: bounce, clawL: clawL, clawR: clawR, eyeOpen: blink)
            }
        }
    }

    // ── ALERT: claws up, startle hop ──
    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)

            MascotTimeline(interval: 0.05) { t in
                let cycle = t.truncatingRemainder(dividingBy: 3.2)
                let pct = CGFloat(cycle / 3.2)
                // Startle: two decaying hops at the start of each cycle.
                let hop: CGFloat
                if pct < 0.12 {
                    hop = -MascotMotion.easeOutBack(pct / 0.12) * 2.6
                } else if pct < 0.26 {
                    hop = -max(0, sin((pct - 0.12) / 0.14 * .pi)) * 1.4
                } else {
                    hop = 0
                }
                let clawsUp: CGFloat = pct < 0.6 ? -2.2 : -1.2  // claws raised high, then easing
                let blink = MascotMotion.blink(t, seed: 0xC1A8)
                return Canvas { c, sz in
                    let v = V(sz)
                    drawLobster(c, v: v, dy: hop, clawL: clawsUp, clawR: clawsUp, eyeOpen: max(0.8, blink))
                }
            }
        }
    }
}
