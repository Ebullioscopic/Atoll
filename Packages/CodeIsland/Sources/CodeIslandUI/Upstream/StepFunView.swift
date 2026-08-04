import SwiftUI

/// StepFunBot — StepFun mascot, pixel-block staircase character.
/// Dark teal #0D9488 with blocky pixel aesthetic matching the step-pattern logo.
struct StepFunView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    private static let bodyC   = Color(red: 0.180, green: 0.750, blue: 0.700) // #2EBFB3 bright teal
    private static let bodyDk  = Color(red: 0.120, green: 0.600, blue: 0.560)
    private static let bodyLt  = Color(red: 0.300, green: 0.870, blue: 0.820)
    private static let faceC   = Color.white
    private static let alertC  = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase  = Color(red: 0.12, green: 0.18, blue: 0.17)
    private static let kbKey   = Color(red: 0.22, green: 0.32, blue: 0.30)
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

    // ── Draw blocky step-pattern body ──
    private func drawBody(_ c: GraphicsContext, v: V, dy: CGFloat,
                          squashX: CGFloat = 1, squashY: CGFloat = 1) {
        let cx: CGFloat = 7.5
        // Main block body
        let bw: CGFloat = 9 * squashX, bh: CGFloat = 7 * squashY
        let bx = cx - bw / 2, by: CGFloat = 7 + (7 - bh) / 2
        c.fill(Path(v.r(bx, by, bw, bh, dy: dy)), with: .color(Self.bodyC))
        // Step accent blocks (top-right corner, like the logo pattern)
        c.fill(Path(v.r(bx + bw - 2.5 * squashX, by - 1.5 * squashY, 2.5 * squashX, 1.5 * squashY, dy: dy)),
               with: .color(Self.bodyLt))
        c.fill(Path(v.r(bx + bw - 5 * squashX, by - 1.5 * squashY, 2.5 * squashX, 1.5 * squashY, dy: dy)),
               with: .color(Self.bodyDk))
    }

    private func drawFace(_ c: GraphicsContext, v: V, dy: CGFloat,
                          blinkPhase: CGFloat = 1.0) {
        let eyeH: CGFloat = 1.5 * blinkPhase
        let eyeY: CGFloat = 10.0 + (1.5 - eyeH) / 2
        c.fill(Path(v.r(5.2, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(Self.faceC))
        c.fill(Path(v.r(8.5, eyeY, 1.3, max(0.3, eyeH), dy: dy)), with: .color(Self.faceC))
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 7, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 15, width, 1)), with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: V, dy: CGFloat = 0) {
        let legDy = dy * 0.3
        c.fill(Path(v.r(5.5, 14, 1, 2, dy: legDy)), with: .color(Self.bodyDk.opacity(0.7)))
        c.fill(Path(v.r(8.5, 14, 1, 2, dy: legDy)), with: .color(Self.bodyDk.opacity(0.7)))
    }

    private var sleepScene: some View {
        ZStack {
            MascotTimeline(interval: 0.12) { t in
                // De-synced dual-sine drift — unique rhythm per mascot (#15).
                let float = sin(t * 2 * .pi / 3.97) * 0.68 + sin(t * 2 * .pi / 6.32) * 0.36
                let blinkCycle = t.truncatingRemainder(dividingBy: 4.0)
                let blink: CGFloat = (blinkCycle > 3.5 && blinkCycle < 3.7) ? 0.15 : 0.5
                Canvas { c, sz in
                    let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)
                    drawShadow(c, v: v, width: 6 + abs(float) * 0.3, opacity: 0.2)
                    drawLegs(c, v: v, dy: float)
                    drawBody(c, v: v, dy: float, squashY: 0.95)
                    drawFace(c, v: v, dy: float, blinkPhase: blink)
                }
            }
            MascotTimeline(interval: 0.12) { t in
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let ci = Double(i)
                        let cycle = 2.8 + ci * 0.3
                        let delay = ci * 0.9
                        let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle)
                        let fontSize = max(6, size * CGFloat(0.18 + phase * 0.10))
                        let baseOp = 0.7 - ci * 0.1
                        let opacity = phase < 0.8 ? baseOp : (1.0 - phase) * 3.5 * baseOp
                        let xOff = size * CGFloat(0.15 + ci * 0.08)
                        let yOff = -size * CGFloat(0.15 + phase * 0.38)
                        Text("z").font(.system(size: fontSize, weight: .black, design: .monospaced))
                            .foregroundStyle(.white.opacity(opacity)).offset(x: xOff, y: yOff)
                    }
                }
            }
        }
    }

    private var workScene: some View {
        MascotTimeline(interval: 0.03) { t in
            let workPause = MascotMotion.quirk(t, cycle: 12.6, duration: 1.2, seed: 0x100d)
            let bounce = sin(t * 2 * .pi / 0.4) * 1.0 * (1 - workPause)
                + sin(t * 2 * .pi / 2.9) * 0.3 * workPause
            let blink = max(0.1, MascotMotion.blink(t, seed: 0x100e))
            let keyPhase = Int(t / 0.1) % 6
            Canvas { c, sz in
                let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
                let shadowW: CGFloat = 7 - abs(bounce) * 0.3
                c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                       with: .color(.black.opacity(max(0.1, 0.35 - abs(bounce) * 0.03))))
                drawLegs(c, v: v, dy: bounce)
                c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
                for row in 0..<2 {
                    let ky = 13.5 + CGFloat(row) * 1.2
                    for col in 0..<6 {
                        c.fill(Path(v.r(0.5 + CGFloat(col) * 2.4, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                    }
                }
                c.fill(Path(v.r(0.5 + CGFloat(keyPhase % 6) * 2.4, 13.5 + CGFloat(keyPhase / 3) * 1.2, 1.8, 0.7)),
                       with: .color(Self.kbHi.opacity(0.9)))
                drawBody(c, v: v, dy: bounce)
                drawFace(c, v: v, dy: bounce, blinkPhase: blink)
            }
        }
    }

    private var alertScene: some View {
        ZStack {
            Circle().fill(Self.alertC.opacity(alive ? 0.12 : 0)).frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)
            MascotTimeline(interval: 0.03) { t in
                let cycle = t.truncatingRemainder(dividingBy: 3.5)
                let pct = cycle / 3.5
                let jumpY = lerp([(0,0),(0.03,0),(0.175,-8),(0.25,1.5),(0.275,-6),(0.35,1),(0.375,-4),(0.45,0.8),(0.475,-2),(0.55,0.3),(0.62,0),(1,0)], at: pct)
                let shakeX: CGFloat = (pct > 0.15 && pct < 0.55) ? sin(pct * 80) * 0.6 : 0
                let bangOp = lerp([(0,0),(0.03,1),(0.55,1),(0.62,0),(1,0)], at: pct)
                Canvas { c, sz in
                    let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
                    let shadowW: CGFloat = 7 * (1.0 - abs(min(0, jumpY)) * 0.04)
                    c.fill(Path(v.r(4 + (7 - shadowW) / 2, 16, shadowW, 1)),
                           with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))
                    drawLegs(c, v: v, dy: jumpY)
                    c.translateBy(x: shakeX * v.s, y: 0)
                    drawBody(c, v: v, dy: jumpY)
                    drawFace(c, v: v, dy: jumpY)
                    c.translateBy(x: -shakeX * v.s, y: 0)
                    if bangOp > 0.01 {
                        c.fill(Path(v.r(13, 4 + jumpY * 0.15, 2, 3.5)), with: .color(Self.alertC.opacity(bangOp)))
                        c.fill(Path(v.r(13, 8 + jumpY * 0.15, 2, 1.5)), with: .color(Self.alertC.opacity(bangOp)))
                    }
                }
            }
        }
    }
}
