import SwiftUI

/// KimiBot — Kimi Code CLI mascot.
/// Soft rounded cube with a small antenna, in Kimi blue.
struct KimiView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    // Kimi brand palette — bright blue
    private static let bodyC  = Color(red: 0.29, green: 0.56, blue: 1.0) // #4A90FF
    private static let bodyDk = Color(red: 0.20, green: 0.42, blue: 0.90) // darker
    private static let bodyLt = Color(red: 0.42, green: 0.68, blue: 1.0) // lighter
    private static let eyeC   = Color.white
    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase = Color(red: 0.18, green: 0.24, blue: 0.34)
    private static let kbKey  = Color(red: 0.38, green: 0.50, blue: 0.64)
    private static let kbHi   = Color.white

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

    private struct V {
        let ox: CGFloat, oy: CGFloat, s: CGFloat, y0: CGFloat
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

    // ── Draw rounded cube body with antenna ──
    private func drawBody(_ c: GraphicsContext, v: V, dy: CGFloat, scale: CGFloat = 1.0) {
        let cx: CGFloat = 7.5, cy: CGFloat = 9.0
        let w: CGFloat = 9 * scale, h: CGFloat = 7 * scale
        let r: CGFloat = 2 * scale
        let rect = CGRect(x: v.ox + (cx - w/2) * v.s,
                          y: v.oy + (cy - h/2 - v.y0 + dy) * v.s,
                          width: w * v.s, height: h * v.s)
        let path = Path(roundedRect: rect, cornerRadius: r * v.s)
        c.fill(path, with: .linearGradient(
            Gradient(colors: [Self.bodyLt, Self.bodyC, Self.bodyDk]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

        // antenna
        let ax = v.ox + cx * v.s
        let ay = v.oy + (cy - h/2 - v.y0 + dy) * v.s
        c.fill(Path(CGRect(x: ax - 0.5 * v.s, y: ay - 2.5 * v.s, width: 1 * v.s, height: 2.5 * v.s)),
               with: .color(Self.bodyDk))
        c.fill(Path(CGRect(x: ax - 1 * v.s, y: ay - 3.5 * v.s, width: 2 * v.s, height: 1.5 * v.s)),
               with: .color(Self.bodyLt))
    }

    // ── Draw dot eyes ──
    private func drawFace(_ c: GraphicsContext, v: V, dy: CGFloat,
                          eyeScale: CGFloat = 1.0, blinkPhase: CGFloat = 1.0) {
        let eyeH: CGFloat = 1.8 * eyeScale * blinkPhase
        let eyeY: CGFloat = 8.5 + (1.8 - eyeH) / 2
        c.fill(Path(v.r(5.0, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(Self.eyeC))
        c.fill(Path(v.r(8.7, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(Self.eyeC))
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 7, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: V, dy: CGFloat = 0) {
        let legDy = dy * 0.3
        c.fill(Path(v.r(5.0, 13.5, 1, 2, dy: legDy)), with: .color(Self.bodyDk.opacity(0.7)))
        c.fill(Path(v.r(9.0, 13.5, 1, 2, dy: legDy)), with: .color(Self.bodyDk.opacity(0.7)))
    }

    // ━━━━━━ SLEEP ━━━━━━
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
                let baseOp = 0.7 - ci * 0.1
                let opacity = phase < 0.8 ? baseOp : (1.0 - phase) * 3.5 * baseOp
                let wave = sin(phase * Double.pi * 2.0) * 0.03
                let xOffsetRatio = 0.15 + ci * 0.08 + wave
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
        let float = sin(t * 2 * .pi / 3.78) * 0.68 + sin(t * 2 * .pi / 6.23) * 0.36
        let blinkCycle = t.truncatingRemainder(dividingBy: 4.0)
        let blink: CGFloat = (blinkCycle > 3.5 && blinkCycle < 3.7) ? 0.15 : 0.5

        return Canvas { c, sz in
            let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 6 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v, dy: float)
            drawBody(c, v: v, dy: float, scale: 0.9)
            drawFace(c, v: v, dy: float, blinkPhase: blink)
        }
    }

    // ━━━━━━ WORK ━━━━━━
    private var workScene: some View {
        MascotTimeline(interval: 0.03) { t in
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        // Work pause: every ~11s the bounce settles for a beat —
        // reading output, not hammering keys nonstop (#15).
        let workPause = MascotMotion.quirk(t, cycle: 10.8, duration: 1.2, seed: 0x35e)
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0 * (1 - workPause)
            + sin(t * 2 * .pi / 2.9) * 0.3 * workPause
        let blink = max(0.1, MascotMotion.blink(t, seed: 0x35f))
        let keyPhase = Int(t / 0.1) % 6

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
            let dy = bounce

            let shadowW: CGFloat = 7 - abs(dy) * 0.3
            c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(dy) * 0.03))))

            drawLegs(c, v: v, dy: dy)

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
            c.fill(Path(v.r(0.5 + CGFloat(flashCol) * 2.4, 13.5 + CGFloat(flashRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawBody(c, v: v, dy: dy, scale: 1.0)
            drawFace(c, v: v, dy: dy, blinkPhase: blink)
        }
    }

    // ━━━━━━ ALERT ━━━━━━
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
        let pulseScale: CGFloat = (pct > 0.03 && pct < 0.55)
            ? 1.0 + sin(pct * 20) * 0.15 : 1.0

        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 7 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v, dy: jumpY)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawBody(c, v: v, dy: jumpY, scale: pulseScale)
            drawFace(c, v: v, dy: jumpY, eyeScale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0)
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
