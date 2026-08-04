import SwiftUI

/// Dex — Codex mascot, pixel-art cloud with terminal prompt face.
/// Inspired by Codex's cloud icon with `>_` symbol. OpenAI black & white style.
struct DexView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    // OpenAI black & white palette — white body, black prompt
    private static let cloudC    = Color(red: 0.92, green: 0.92, blue: 0.93) // off-white
    private static let cloudDark = Color(red: 0.70, green: 0.70, blue: 0.72) // legs
    private static let promptC   = Color.black
    private static let alertC    = Color(red: 1.0, green: 0.55, blue: 0.0)   // amber warning
    private static let kbBase    = Color(red: 0.18, green: 0.18, blue: 0.20)
    private static let kbKey     = Color(red: 0.40, green: 0.40, blue: 0.42)
    private static let kbHi      = Color.white

    var body: some View {
        ZStack {
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

    // ── Coordinate helper ──
    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat
        let y0: CGFloat

        init(_ sz: CGSize, svgW: CGFloat = 15, svgH: CGFloat = 10, svgY0: CGFloat = 6) {
            s = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

    // Interpolate between keyframes
    private func lerp(_ keyframes: [(CGFloat, CGFloat)], at pct: CGFloat) -> CGFloat {
        guard let first = keyframes.first else { return 0 }
        if pct <= first.0 { return first.1 }
        for i in 1..<keyframes.count {
            if pct <= keyframes[i].0 {
                let t = (pct - keyframes[i-1].0) / (keyframes[i].0 - keyframes[i-1].0)
                return keyframes[i-1].1 + (keyframes[i].1 - keyframes[i-1].1) * t
            }
        }
        return keyframes.last?.1 ?? 0
    }

    // ── Cloud body: a pixel-art blob shape ──
    // Rounded cloud made of overlapping rects (8-bit style)
    private func drawCloud(_ c: GraphicsContext, v: V, dy: CGFloat,
                           squashX: CGFloat = 1, squashY: CGFloat = 1) {
        let cc = Self.cloudC

        // Center offset for squash
        let cx: CGFloat = 7.5
        func sx(_ x: CGFloat, w: CGFloat) -> (CGFloat, CGFloat) {
            let nx = cx + (x - cx) * squashX
            return (nx, w * squashX)
        }

        // Cloud body — flat black, pixel blob shape
        let rows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (14, 4, 7),       // bottom
            (13, 3, 9),
            (12, 2, 11),
            (11, 1, 13),      // widest
            (10, 1, 13),
            (9,  1, 13),
            (8,  2, 11),
            (7,  2, 11),
            // Top bumps (cloud silhouette)
            (6,  3, 3),       // left bump
            (6,  6, 3),       // center bump
            (6,  9, 3),       // right bump
            (5,  4, 2),       // left bump top
            (5,  6.5, 2),     // center bump top
            (5,  9, 2),       // right bump top
        ]

        for row in rows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            let adjH: CGFloat = 1 * squashY
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 10, adjW, adjH, dy: dy)),
                   with: .color(cc))
        }
    }

    // ── Draw `>_` terminal prompt as face ──
    private func drawPrompt(_ c: GraphicsContext, v: V, dy: CGFloat,
                            color: Color = Self.promptC, cursorOn: Bool = true) {
        // `>` chevron — pixel art
        c.fill(Path(v.r(3, 10, 1, 1, dy: dy)), with: .color(color))
        c.fill(Path(v.r(4, 11, 1, 1, dy: dy)), with: .color(color))
        c.fill(Path(v.r(3, 12, 1, 1, dy: dy)), with: .color(color))

        // `_` cursor
        if cursorOn {
            c.fill(Path(v.r(6, 12, 3, 1, dy: dy)), with: .color(color))
        }
    }

    // ── Shadow ──
    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    // ── Small legs (pixel stubs under cloud) ──
    private func drawLegs(_ c: GraphicsContext, v: V) {
        c.fill(Path(v.r(5, 14.5, 1, 1.5)), with: .color(Self.cloudDark))
        c.fill(Path(v.r(9, 14.5, 1, 1.5)), with: .color(Self.cloudDark))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // SLEEP — floating gently, cursor blinking slow
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var sleepScene: some View {
        ZStack {
            MascotTimeline(interval: 0.12) { t in
                sleepCanvas(t: t)
            }
            MascotTimeline(interval: 0.12) { t in
                floatingZs(t: t)
            }
        }
    }

    private func floatingZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let ci = Double(i)
                let cycle = 2.8 + ci * 0.3
                let delay = ci * 0.9
                let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle)
                let fontSize = max(6, size * CGFloat(0.18 + phase * 0.10))
                let baseOpacity = 0.7 - ci * 0.1
                let opacity = phase < 0.8 ? baseOpacity : (1.0 - phase) * 3.5 * baseOpacity
                let wave = sin(phase * Double.pi * 2.0) * 0.03
                let xOffsetRatio = 0.08 + ci * 0.06 + wave
                let xOff = size * CGFloat(xOffsetRatio)
                let yOff = -size * CGFloat(0.15 + phase * 0.38)
                Text("z")
                    .font(.system(size: fontSize, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .offset(x: xOff, y: yOff)
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        // Cloud drift: two incommensurate sines — the float never quite repeats,
        // which is exactly how a cloud should behave (#15).
        let float = sin(t * 2 * .pi / 4.0) * 0.7 + sin(t * 2 * .pi / 6.3) * 0.35
        // Standby heartbeat: mostly a slow blink, but every ~8s the cursor gives
        // a quick double-pulse — a terminal dreaming in its sleep.
        let pulse = MascotMotion.quirk(t, cycle: 8.0, duration: 0.5, seed: 0xDE1)
        let cursorPhase = t.truncatingRemainder(dividingBy: 1.2)
        let cursorOn = pulse > 0 ? (pulse * 4).truncatingRemainder(dividingBy: 1) < 0.5 : cursorPhase < 0.6

        return Canvas { c, sz in
            let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)

            drawShadow(c, v: v, width: 7 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v)
            drawCloud(c, v: v, dy: float)
            // Sleep: only show dim cursor (no `>` chevron = mouth closed)
            if cursorOn {
                c.fill(Path(v.r(6, 12, 3, 1, dy: float)),
                       with: .color(Self.promptC.opacity(pulse > 0 ? 0.5 : 0.3)))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // WORK — bouncing, cursor active, typing on keyboard
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var workScene: some View {
        MascotTimeline(interval: 0.03) { t in
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        // Compile-wait pause: every ~12s the terminal stops hammering keys for
        // a moment (cursor steady, bounce settles) — output is "scrolling" (#15).
        let pause = MascotMotion.quirk(t, cycle: 12.0, duration: 1.2, seed: 0xDE2)
        let intensity = 1.0 - Double(pause)
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0 * intensity

        // Cursor rapid blink while typing; solid during the pause (busy, not idle).
        let cursorPhase = t.truncatingRemainder(dividingBy: 0.3)
        let cursorOn = pause > 0.3 ? true : cursorPhase < 0.15

        // Key flash with humanized stroke cadence — skipped strokes read as bursts.
        let stroke = MascotMotion.typingStroke(t, cadence: 0.1, seed: 0xDE3)
        let keyPhase = Int(MascotMotion.hash01(stroke.slot, seed: 0xDE4) * 6)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
            let dy = bounce

            // Shadow
            let shadowW: CGFloat = 8 - abs(dy) * 0.3
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(dy) * 0.03))))

            drawLegs(c, v: v)

            // Keyboard
            c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
            for row in 0..<2 {
                let ky = 13.5 + CGFloat(row) * 1.2
                for col in 0..<6 {
                    let kx = 0.5 + CGFloat(col) * 2.4
                    c.fill(Path(v.r(kx, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                }
            }
            // Key flash — only on real strokes, and never during the pause
            if stroke.active && pause < 0.3 {
                let flashRow = keyPhase / 3
                let flashCol = keyPhase % 6
                let fkx = 0.5 + CGFloat(flashCol) * 2.4
                let fky = 13.5 + CGFloat(flashRow) * 1.2
                c.fill(Path(v.r(fkx, fky, 1.8, 0.7)), with: .color(Self.kbHi.opacity(0.9)))
            }

            drawCloud(c, v: v, dy: dy)
            drawPrompt(c, v: v, dy: dy, cursorOn: cursorOn)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ALERT — shaking, prompt flashing amber
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)

            MascotTimeline(interval: 0.03) { t in
                alertCanvas(t: t)
            }
        }
    }

    private func alertCanvas(t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        let pct = cycle / 3.5

        let jumpY = lerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -8), (0.20, -8), (0.25, 1.5),
            (0.275, -6), (0.30, -6), (0.35, 1.0),
            (0.375, -4), (0.40, -4), (0.45, 0.8),
            (0.475, -2), (0.50, -2), (0.55, 0.3),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        let squashX: CGFloat = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
        let squashY: CGFloat = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0

        // Shake
        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0

        // Prompt flashing between white and amber
        let flash = (pct > 0.03 && pct < 0.55) ? sin(pct * 25) * 0.5 + 0.5 : 0.0
        let promptColor = flash > 0.5 ? Self.alertC : Self.promptC

        // ! mark
        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            // Shadow
            let shadowW: CGFloat = 8 * (1.0 - abs(min(0, jumpY)) * 0.04)
            let shadowOp = max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(shadowOp)))

            drawLegs(c, v: v)

            // Cloud body with shake offset — draw manually with offset
            // Since drawCloud doesn't take shakeX, we apply transform
            c.translateBy(x: shakeX * v.s, y: 0)
            drawCloud(c, v: v, dy: jumpY, squashX: squashX, squashY: squashY)
            drawPrompt(c, v: v, dy: jumpY, color: promptColor, cursorOn: true)
            c.translateBy(x: -shakeX * v.s, y: 0)

            // ! mark
            if bangOp > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 13
                let by: CGFloat = 4 + jumpY * 0.15
                c.fill(Path(v.r(bx, by, bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale, bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
            }
        }
    }
}
