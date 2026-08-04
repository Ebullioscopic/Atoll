import SwiftUI

/// CopilotBot — GitHub Copilot CLI mascot, adapted from copilot-avatar.svg.
/// Two hollow ear loops (╭─╮╭─╮) on top, rose-framed face with gold dot eyes,
/// and a pink mouth bar — a cute, minimal character.
struct CopilotView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    // Palette from copilot-avatar.svg
    private static let earC    = Color(red: 0.20, green: 0.20, blue: 0.20)  // #333 ear loops
    private static let bodyC   = Color(red: 0.80, green: 0.20, blue: 0.40)  // #cc3366 rose/magenta
    private static let faceC   = Color(red: 0.13, green: 0.13, blue: 0.16)  // dark face screen
    private static let eyeC    = Color(red: 1.00, green: 0.84, blue: 0.00)  // #ffd700 gold
    private static let alertC  = Color(red: 1.00, green: 0.30, blue: 0.15)  // #FE4C25 alert orange
    private static let kbBase  = Color(red: 0.12, green: 0.08, blue: 0.10)
    private static let kbKey   = Color(red: 0.35, green: 0.15, blue: 0.22)
    private static let kbHi    = Color.white

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

        init(_ sz: CGSize, svgW: CGFloat = 15, svgH: CGFloat = 12, svgY0: CGFloat = 4) {
            s = min(sz.width / svgW, sz.height / svgH)
            ox = (sz.width - svgW * s) / 2
            oy = (sz.height - svgH * s) / 2
            y0 = svgY0
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dy: CGFloat = 0) -> CGRect {
            CGRect(x: ox + x * s, y: oy + (y - y0 + dy) * s, width: w * s, height: h * s)
        }
    }

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

    // ── Ear loops — two hollow rounded-rect outlines (╭─╮╭─╮ / ╰─╯╰─╯) ──
    private func drawEars(_ c: GraphicsContext, v: V, dy: CGFloat,
                          color: Color? = nil, signal: Bool = false) {
        let ec = color ?? Self.earC
        // Left ear loop (3×3 outlined rect)
        c.fill(Path(v.r(3, 5, 3, 1, dy: dy)), with: .color(ec))   // top ╭─╮
        c.fill(Path(v.r(3, 6, 1, 1, dy: dy)), with: .color(ec))   // left │
        c.fill(Path(v.r(5, 6, 1, 1, dy: dy)), with: .color(ec))   // right │
        c.fill(Path(v.r(3, 7, 3, 1, dy: dy)), with: .color(ec))   // bottom ╰─╯
        // Right ear loop
        c.fill(Path(v.r(9, 5, 3, 1, dy: dy)), with: .color(ec))
        c.fill(Path(v.r(9, 6, 1, 1, dy: dy)), with: .color(ec))
        c.fill(Path(v.r(11, 6, 1, 1, dy: dy)), with: .color(ec))
        c.fill(Path(v.r(9, 7, 3, 1, dy: dy)), with: .color(ec))
        // Stems connecting ears to body
        c.fill(Path(v.r(4, 8, 1, 1, dy: dy)), with: .color(ec))
        c.fill(Path(v.r(10, 8, 1, 1, dy: dy)), with: .color(ec))
        // Signal flash inside loops (work mode: receiving data)
        if signal {
            c.fill(Path(v.r(4, 6, 1, 1, dy: dy)), with: .color(Self.eyeC.opacity(0.5)))
            c.fill(Path(v.r(10, 6, 1, 1, dy: dy)), with: .color(Self.eyeC.opacity(0.5)))
        }
    }

    // ── Body — rose frame with dark face screen ──
    private func drawBody(_ c: GraphicsContext, v: V, dy: CGFloat,
                          shellColor: Color? = nil) {
        let bc = shellColor ?? Self.bodyC
        // Rose shell frame
        c.fill(Path(v.r(2, 9, 11, 1, dy: dy)), with: .color(bc))    // top bar
        c.fill(Path(v.r(2, 10, 2, 3, dy: dy)), with: .color(bc))    // left cheek
        c.fill(Path(v.r(11, 10, 2, 3, dy: dy)), with: .color(bc))   // right cheek
        // Dark face screen (between cheeks)
        c.fill(Path(v.r(4, 10, 7, 3, dy: dy)), with: .color(Self.faceC))
        // Bottom bar + chin (drawn after face to stay on top)
        c.fill(Path(v.r(2, 13, 11, 1, dy: dy)), with: .color(bc))   // bottom bar ▔▔▔▔
        c.fill(Path(v.r(4, 14, 7, 1, dy: dy)), with: .color(bc))    // chin
    }

    // ── Eyes — gold dots (▘▝ quarter-block style) ──
    private func drawEyes(_ c: GraphicsContext, v: V, dy: CGFloat,
                          color: Color? = nil, height: CGFloat = 1) {
        let ec = color ?? Self.eyeC
        c.fill(Path(v.r(5, 10, 1, height, dy: dy)), with: .color(ec))
        c.fill(Path(v.r(9, 10, 1, height, dy: dy)), with: .color(ec))
    }

    // ── Legs ──
    private func drawLegs(_ c: GraphicsContext, v: V) {
        c.fill(Path(v.r(6, 14.5, 1, 1.5)), with: .color(Self.bodyC.opacity(0.6)))
        c.fill(Path(v.r(8, 14.5, 1, 1.5)), with: .color(Self.bodyC.opacity(0.6)))
    }

    // ── Shadow ──
    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // SLEEP — gentle float, dim face, Z's
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
        // Two incommensurate drift periods — the float never quite repeats,
        // and every mascot has its own rhythm so multi-session rows don't sync (#15).
        let float = sin(t * 2 * .pi / 4.21) * 0.68 + sin(t * 2 * .pi / 6.85) * 0.36

        return Canvas { c, sz in
            let v = V(sz)
            drawShadow(c, v: v, width: 7 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v)
            drawEars(c, v: v, dy: float)
            drawBody(c, v: v, dy: float, shellColor: Self.bodyC.opacity(0.4))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // WORK — bouncing, blinking, ear signals, keyboard
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var workScene: some View {
        MascotTimeline(interval: 0.03) { t in
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        // Work pause: every ~12s the bounce settles for a beat —
        // reading output, not hammering keys nonstop (#15).
        let workPause = MascotMotion.quirk(t, cycle: 11.6, duration: 1.2, seed: 0x8f8)
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0 * (1 - workPause)
            + sin(t * 2 * .pi / 2.9) * 0.3 * workPause
        let keyPhase = Int(t / 0.1) % 6

        // Blink
        let blinkCycle = t.truncatingRemainder(dividingBy: 3.2)
        let showEyes = !(blinkCycle > 1.5 && blinkCycle < 1.6)

        // Ear signal pulse (brief gold flash inside loops every ~2.5s)
        let sigPhase = t.truncatingRemainder(dividingBy: 2.5)
        let earSignal = sigPhase > 2.0 && sigPhase < 2.3

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
            let flashRow = keyPhase / 3
            let flashCol = keyPhase % 6
            let fkx = 0.5 + CGFloat(flashCol) * 2.4
            let fky = 13.5 + CGFloat(flashRow) * 1.2
            c.fill(Path(v.r(fkx, fky, 1.8, 0.7)), with: .color(Self.kbHi.opacity(0.9)))

            drawEars(c, v: v, dy: dy, signal: earSignal)
            drawBody(c, v: v, dy: dy)
            if showEyes { drawEyes(c, v: v, dy: dy) }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ALERT — jumping, ear flash, eye startle
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

        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0

        // Flash ears and cheeks between normal and alert orange
        let flash = (pct > 0.03 && pct < 0.55) ? sin(pct * 25) * 0.5 + 0.5 : 0.0
        let earColor = flash > 0.5 ? Self.alertC : Self.earC
        let shellColor = flash > 0.5 ? Self.alertC : Self.bodyC

        // Eyes widen during startle (1px → 2px tall)
        let eyeH: CGFloat = (pct > 0.03 && pct < 0.55) ? 2 : 1

        // ! mark
        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 * (1.0 - abs(min(0, jumpY)) * 0.04)
            let shadowOp = max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(shadowOp)))

            drawLegs(c, v: v)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawEars(c, v: v, dy: jumpY, color: earColor)
            drawBody(c, v: v, dy: jumpY, shellColor: shellColor)
            drawEyes(c, v: v, dy: jumpY, height: eyeH)
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
