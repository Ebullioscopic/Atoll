import SwiftUI

/// OpBot — OpenCode mascot, pixel-art dark terminal block with `{ }` face.
/// Minimalist geometric style matching OpenCode's monochrome branding.
struct OpenCodeView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    // OpenCode monochrome palette
    private static let bodyC    = Color(red: 0.22, green: 0.22, blue: 0.24) // #383838 dark gray
    private static let frameC   = Color(red: 0.55, green: 0.55, blue: 0.57) // #8C8C91 light gray frame
    private static let faceC    = Color(red: 0.85, green: 0.85, blue: 0.87) // #D9D9DE light face
    private static let legC     = Color(red: 0.35, green: 0.35, blue: 0.37)
    private static let alertC   = Color(red: 1.0, green: 0.55, blue: 0.0)   // amber
    private static let kbBase   = Color(red: 0.12, green: 0.12, blue: 0.14)
    private static let kbKey    = Color(red: 0.30, green: 0.30, blue: 0.32)
    private static let kbHi     = Color.white

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

    // ── Draw block body — geometric square with inner frame ──
    private func drawBlock(_ c: GraphicsContext, v: V, dy: CGFloat,
                           squashX: CGFloat = 1, squashY: CGFloat = 1) {
        let cx: CGFloat = 7.5

        func sx(_ x: CGFloat, w: CGFloat) -> (CGFloat, CGFloat) {
            let nx = cx + (x - cx) * squashX
            return (nx, w * squashX)
        }

        // Outer body (dark square block)
        let bodyRows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (5,  3, 9),   // top
            (6,  2, 11),
            (7,  2, 11),
            (8,  2, 11),
            (9,  2, 11),
            (10, 2, 11),
            (11, 2, 11),
            (12, 2, 11),
            (13, 3, 9),   // bottom
        ]
        for row in bodyRows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            let adjH: CGFloat = 1 * squashY
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 10, adjW, adjH, dy: dy)),
                   with: .color(Self.bodyC))
        }

        // Inner frame (light gray border, 1px inset)
        let frameRows: [(y: CGFloat, x: CGFloat, w: CGFloat)] = [
            (6,  3, 9),   // top edge
            (12, 3, 9),   // bottom edge
        ]
        for row in frameRows {
            let (adjX, adjW) = sx(row.x, w: row.w)
            c.fill(Path(v.r(adjX, row.y * squashY + (1 - squashY) * 10, adjW, 0.7 * squashY, dy: dy)),
                   with: .color(Self.frameC.opacity(0.6)))
        }
        // Left and right edges
        for y: CGFloat in stride(from: 7, to: 12, by: 1) {
            let (lx, _) = sx(3, w: 0.7)
            c.fill(Path(v.r(lx, y * squashY + (1 - squashY) * 10, 0.7 * squashX, 1 * squashY, dy: dy)),
                   with: .color(Self.frameC.opacity(0.4)))
            let (rx, _) = sx(11.3, w: 0.7)
            c.fill(Path(v.r(rx, y * squashY + (1 - squashY) * 10, 0.7 * squashX, 1 * squashY, dy: dy)),
                   with: .color(Self.frameC.opacity(0.4)))
        }
    }

    // ── Draw face — `{ }` brackets ──
    private func drawFace(_ c: GraphicsContext, v: V, dy: CGFloat,
                          color: Color = Self.faceC, eyeScale: CGFloat = 1.0) {
        let eyeH: CGFloat = 2.0 * eyeScale
        let eyeY: CGFloat = 8.5 + (2.0 - eyeH) / 2

        // Left bracket `{`
        c.fill(Path(v.r(4.5, eyeY, 0.8, max(0.3, eyeH), dy: dy)), with: .color(color))
        c.fill(Path(v.r(4.0, eyeY + eyeH * 0.3, 0.7, max(0.3, eyeH * 0.4), dy: dy)), with: .color(color))

        // Right bracket `}`
        c.fill(Path(v.r(9.7, eyeY, 0.8, max(0.3, eyeH), dy: dy)), with: .color(color))
        c.fill(Path(v.r(10.2, eyeY + eyeH * 0.3, 0.7, max(0.3, eyeH * 0.4), dy: dy)), with: .color(color))

        // Center dot (cursor)
        if eyeScale > 0.5 {
            c.fill(Path(v.r(7.1, 9.2, 0.8, 0.8, dy: dy)), with: .color(color.opacity(0.8)))
        }
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 14.5, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: V) {
        c.fill(Path(v.r(4, 13.5, 1, 1.5)), with: .color(Self.legC))
        c.fill(Path(v.r(10, 13.5, 1, 1.5)), with: .color(Self.legC))
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
                Text("z")
                    .font(.system(size: fontSize, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(opacity))
                    .offset(x: size * CGFloat(0.15 + ci * 0.08),
                            y: -size * CGFloat(0.15 + phase * 0.38))
            }
        }
    }

    private func sleepCanvas(t: Double) -> some View {
        // Two incommensurate drift periods — the float never quite repeats,
        // and every mascot has its own rhythm so multi-session rows don't sync (#15).
        let float = sin(t * 2 * .pi / 3.85) * 0.68 + sin(t * 2 * .pi / 7.24) * 0.36

        return Canvas { c, sz in
            let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)
            drawShadow(c, v: v, width: 7 + abs(float) * 0.3, opacity: 0.2)
            drawLegs(c, v: v)
            drawBlock(c, v: v, dy: float)
            drawFace(c, v: v, dy: float, color: Self.faceC.opacity(0.4), eyeScale: 0.3)
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
        let workPause = MascotMotion.quirk(t, cycle: 11.1, duration: 1.2, seed: 0xc88)
        let bounce = sin(t * 2 * .pi / 0.4) * 1.0 * (1 - workPause)
            + sin(t * 2 * .pi / 2.9) * 0.3 * workPause
        let blink = max(0.1, MascotMotion.blink(t, seed: 0xc89))
        let keyPhase = Int(t / 0.1) % 6

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 - abs(bounce) * 0.3
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(bounce) * 0.03))))

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
            let fCol = keyPhase % 6
            let fRow = keyPhase / 3
            c.fill(Path(v.r(0.5 + CGFloat(fCol) * 2.4, 13.5 + CGFloat(fRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawBlock(c, v: v, dy: bounce)
            drawFace(c, v: v, dy: bounce, eyeScale: blink)
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

        let squashX: CGFloat = jumpY > 0.5 ? 1.0 + jumpY * 0.03 : 1.0
        let squashY: CGFloat = jumpY > 0.5 ? 1.0 - jumpY * 0.02 : 1.0
        let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0

        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)

            let shadowW: CGFloat = 8 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(4 + (8 - shadowW) / 2, 16, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawBlock(c, v: v, dy: jumpY, squashX: squashX, squashY: squashY)
            drawFace(c, v: v, dy: jumpY, eyeScale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0)
            c.translateBy(x: -shakeX * v.s, y: 0)

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
