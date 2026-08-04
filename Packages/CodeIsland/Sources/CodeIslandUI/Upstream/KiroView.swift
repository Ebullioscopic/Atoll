import SwiftUI

/// Kiro mascot — a pixel ghost after Kiro's (AWS) ghost logo. Soft white body
/// with a violet tint, wavy hem, big friendly eyes. Previously Kiro sessions
/// fell back to Clawd; now the ghost gets its own seat.
struct KiroView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27

    private static let bodyC = Color(red: 0.93, green: 0.92, blue: 0.99)
    private static let bodyShade = Color(red: 0.78, green: 0.74, blue: 0.95)
    private static let eyeC = Color(red: 0.28, green: 0.20, blue: 0.55)
    private static let alertC = Color(red: 0.62, green: 0.45, blue: 1.0)

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

    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat, y0: CGFloat
        init(_ sz: CGSize, svgW: CGFloat = 14, svgH: CGFloat = 14, svgY0: CGFloat = 2) {
            s = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

    /// Ghost body with a 3-tooth wavy hem. `hemPhase` scrolls the wave,
    /// `eyeOpen` scales pupils, `lean` tilts the eyes for a "focused" look.
    private func drawGhost(
        _ c: GraphicsContext, v: V, dy: CGFloat,
        hemPhase: Int, eyeOpen: CGFloat, lean: CGFloat = 0, shadow: Bool = true
    ) {
        if shadow {
            c.fill(Path(v.r(4, 14.5, 6, 1)), with: .color(.black.opacity(0.25)))
        }
        // Dome + body
        c.fill(Path(v.r(4, 3, 6, 2, dy: dy)), with: .color(Self.bodyC))
        c.fill(Path(v.r(3, 5, 8, 7, dy: dy)), with: .color(Self.bodyC))
        // Hem: three teeth, alternating up/down with hemPhase for a float-wobble
        for i in 0..<3 {
            let up = (i + hemPhase) % 2 == 0
            let x = 3 + CGFloat(i) * 2.7
            c.fill(Path(v.r(x, 12, 2.2, up ? 1.4 : 0.8, dy: dy)), with: .color(Self.bodyC))
        }
        // Side shade for volume
        c.fill(Path(v.r(9.9, 5.5, 1.1, 6, dy: dy)), with: .color(Self.bodyShade.opacity(0.55)))
        // Eyes
        let eyeH = max(0.3, 2.2 * eyeOpen)
        let eyeY = 6.4 + (2.2 - eyeH) / 2
        c.fill(Path(v.r(4.7 + lean, eyeY, 1.4, eyeH, dy: dy)), with: .color(Self.eyeC))
        c.fill(Path(v.r(7.7 + lean, eyeY, 1.4, eyeH, dy: dy)), with: .color(Self.eyeC))
    }

    // ── SLEEP: slow drift, hem sway, long blinks, Z's ──
    private var sleepScene: some View {
        ZStack {
            MascotTimeline(interval: 0.12) { t in
                let float = sin(t * 2 * .pi / 4.4) * 0.7 + sin(t * 2 * .pi / 6.9) * 0.35
                let hemPhase = Int(t / 0.9) % 2
                // Ghost dozes with eyes nearly shut; a rare slow re-open quirk.
                let stir = MascotMotion.quirk(t, cycle: 8.5, duration: 1.0, seed: 0x419A)
                return Canvas { c, sz in
                    let v = V(sz)
                    drawGhost(c, v: v, dy: float, hemPhase: hemPhase, eyeOpen: 0.15 + stir * 0.5, shadow: false)
                }
            }
            MascotTimeline(interval: 0.12) { t in
                ForEach(0..<2, id: \.self) { i in
                    let ci = Double(i)
                    let cycle = 3.1 + ci * 0.4
                    let p = max(0, ((t - ci * 1.2).truncatingRemainder(dividingBy: cycle)) / cycle)
                    let fontSize: CGFloat = max(6, size * CGFloat(0.15 + p * 0.08))
                    let opacity: Double = p < 0.8 ? 0.55 - ci * 0.15 : (1 - p) * 3 * 0.55
                    let dx = size * CGFloat(0.14 + ci * 0.05)
                    let dy = -size * CGFloat(0.14 + p * 0.32)
                    Text("z")
                        .font(.system(size: fontSize, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(opacity))
                        .offset(x: dx, y: dy)
                }
            }
        }
    }

    // ── WORK: focused hover-bob, eyes lean into the work, natural blinks ──
    private var workScene: some View {
        MascotTimeline(interval: 0.05) { t in
            let pause = MascotMotion.quirk(t, cycle: 11.5, duration: 1.2, seed: 0x419B)
            let intensity = 1.0 - pause
            let bob = sin(t * 2 * .pi / 0.45) * 0.8 * intensity
                + sin(t * 2 * .pi / 2.9) * 0.3 * pause
            let hemPhase = Int(t / 0.25) % 2
            let blink = MascotMotion.blink(t, seed: 0x419C)
            // Eyes lean right while "reading", straighten during the pause.
            let lean = 0.4 * intensity
            return Canvas { c, sz in
                let v = V(sz)
                drawGhost(c, v: v, dy: bob, hemPhase: hemPhase, eyeOpen: blink, lean: lean)
            }
        }
    }

    // ── ALERT: startle rise + wide eyes ──
    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.14 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)

            MascotTimeline(interval: 0.05) { t in
                let cycle = t.truncatingRemainder(dividingBy: 3.4)
                let pct = CGFloat(cycle / 3.4)
                let rise: CGFloat
                if pct < 0.14 {
                    rise = -MascotMotion.easeOutBack(pct / 0.14) * 2.2
                } else if pct < 0.3 {
                    rise = -1.6 - sin((pct - 0.14) / 0.16 * .pi) * 0.5
                } else {
                    rise = -1.2
                }
                let hemPhase = Int(t / 0.18) % 2  // hem flutters when agitated
                return Canvas { c, sz in
                    let v = V(sz)
                    drawGhost(c, v: v, dy: rise, hemPhase: hemPhase, eyeOpen: 1.3)
                }
            }
        }
    }
}
