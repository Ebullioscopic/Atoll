import SwiftUI
import CodeIslandCore

/// PiBot — Pi / Oh My Pi mascot, a tiny teal terminal with a pixel π face.
/// Deep teal shell + cyan highlights so it reads as Pi without defaulting to “generic green CLI”.
struct PiView: View {
    let status: AgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    private static let shellC = Color(red: 0.14, green: 0.49, blue: 0.53)
    private static let shellDk = Color(red: 0.09, green: 0.30, blue: 0.34)
    private static let leafC = Color(red: 0.44, green: 0.90, blue: 0.95)
    private static let faceC = Color(red: 0.05, green: 0.12, blue: 0.13)
    private static let alertC = Color(red: 1.0, green: 0.35, blue: 0.14)
    private static let kbBase = Color(red: 0.08, green: 0.13, blue: 0.16)
    private static let kbKey = Color(red: 0.13, green: 0.23, blue: 0.27)
    private static let kbHi = Color(red: 0.72, green: 0.96, blue: 1.0)

    var body: some View {
        ZStack {
            switch status {
            case .idle:
                sleepScene
            case .processing, .running:
                workScene
            case .waitingApproval, .waitingQuestion:
                alertScene
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

        init(_ sz: CGSize, svgW: CGFloat = 16, svgH: CGFloat = 12, svgY0: CGFloat = 4) {
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
                let t = (pct - keyframes[i - 1].0) / (keyframes[i].0 - keyframes[i - 1].0)
                return keyframes[i - 1].1 + (keyframes[i].1 - keyframes[i - 1].1) * t
            }
        }
        return keyframes.last?.1 ?? 0
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 7, opacity: Double = 0.28) {
        c.fill(Path(v.r(8 - width / 2, 15, width, 1)), with: .color(.black.opacity(opacity)))
    }

    private func drawFeet(_ c: GraphicsContext, v: V, dy: CGFloat) {
        let footDy = dy * 0.25
        c.fill(Path(v.r(5.5, 13.8, 1.2, 1.5, dy: footDy)), with: .color(Self.shellDk.opacity(0.75)))
        c.fill(Path(v.r(9.3, 13.8, 1.2, 1.5, dy: footDy)), with: .color(Self.shellDk.opacity(0.75)))
    }

    private func drawLeaf(_ c: GraphicsContext, v: V, dy: CGFloat) {
        c.fill(Path(ellipseIn: v.r(5.7, 2.2, 2.2, 1.3, dy: dy)), with: .color(Self.leafC))
        c.fill(Path(ellipseIn: v.r(8.0, 1.8, 2.6, 1.5, dy: dy)), with: .color(Self.leafC))
        c.fill(Path(v.r(7.8, 2.8, 0.4, 1.0, dy: dy)), with: .color(Self.shellDk))
    }

    private func drawBody(_ c: GraphicsContext, v: V, dy: CGFloat, scale: CGFloat = 1.0) {
        let cx: CGFloat = 8
        let cy: CGFloat = 9.5
        let bw: CGFloat = 8.8 * scale
        let bh: CGFloat = 6.6 * scale
        let bodyRect = v.r(cx - bw / 2, cy - bh / 2, bw, bh, dy: dy)
        c.fill(Path(roundedRect: bodyRect, cornerRadius: 1.6 * v.s), with: .color(Self.shellC))
        c.fill(Path(v.r(cx - bw / 2 + 0.6, cy - bh / 2 + 0.6, bw - 1.2, 0.7, dy: dy)), with: .color(.white.opacity(0.18)))
        c.fill(Path(v.r(cx - bw / 2, cy + bh / 2 - 1.2, bw, 1.2, dy: dy)), with: .color(Self.shellDk.opacity(0.8)))
        drawLeaf(c, v: v, dy: dy)
    }

    private func drawPiFace(_ c: GraphicsContext, v: V, dy: CGFloat, eyeScale: CGFloat = 1.0, color: Color = Self.faceC) {
        let eyeH = max(0.2, 1.0 * eyeScale)
        c.fill(Path(v.r(5.4, 8.0 + (1 - eyeH) * 0.3, 1.3, eyeH, dy: dy)), with: .color(color))
        c.fill(Path(v.r(9.3, 8.0 + (1 - eyeH) * 0.3, 1.3, eyeH, dy: dy)), with: .color(color))
        c.fill(Path(v.r(6.2, 9.8, 3.6, 0.6, dy: dy)), with: .color(color))
        c.fill(Path(v.r(6.6, 9.4, 0.6, 2.0, dy: dy)), with: .color(color))
        c.fill(Path(v.r(8.8, 9.4, 0.6, 2.0, dy: dy)), with: .color(color))
    }

    private var sleepScene: some View {
        ZStack {
            MascotTimeline(interval: 0.12) { t in
                // De-synced dual-sine drift — unique rhythm per mascot (#15).
                let float = sin(t * 2 * .pi / 4.04) * 0.59 + sin(t * 2 * .pi / 6.87) * 0.32
                let blinkCycle = t.truncatingRemainder(dividingBy: 4.0)
                let blink: CGFloat = (blinkCycle > 3.5 && blinkCycle < 3.7) ? 0.15 : 1.0
                Canvas { c, sz in
                    let v = V(sz)
                    drawShadow(c, v: v, width: 6.4 + abs(float) * 0.3, opacity: 0.18)
                    drawFeet(c, v: v, dy: float)
                    drawBody(c, v: v, dy: float, scale: 0.94)
                    drawPiFace(c, v: v, dy: float, eyeScale: blink)
                }
            }
            MascotTimeline(interval: 0.12) { t in
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let ci = Double(i)
                        let cycle = 2.6 + ci * 0.25
                        let delay = ci * 0.9
                        let phase = max(0, ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle)
                        let fontSize = max(6, size * CGFloat(0.18 + phase * 0.10))
                        let opacity = phase < 0.8 ? (0.72 - ci * 0.1) : (1.0 - phase) * 3.5 * (0.72 - ci * 0.1)
                        Text("z")
                            .font(.system(size: fontSize, weight: .black, design: .monospaced))
                            .foregroundStyle(Self.faceC.opacity(opacity))
                            .offset(x: size * CGFloat(0.16 + ci * 0.08), y: -size * CGFloat(0.18 + phase * 0.36))
                    }
                }
            }
        }
    }

    private var workScene: some View {
        MascotTimeline(interval: 0.03) { t in
            let bounce = sin(t * 2 * .pi / 0.42) * 0.9
            let blink = max(0.1, MascotMotion.blink(t, seed: 0x9bb))
            let keyPhase = Int(t / 0.1) % 6
            Canvas { c, sz in
                let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
                drawShadow(c, v: v, width: 7 - abs(bounce) * 0.25, opacity: max(0.1, 0.32 - abs(bounce) * 0.02))
                drawFeet(c, v: v, dy: bounce)
                c.fill(Path(v.r(0, 13, 15, 3)), with: .color(Self.kbBase))
                for row in 0..<2 {
                    let ky = 13.45 + CGFloat(row) * 1.15
                    for col in 0..<6 {
                        c.fill(Path(v.r(0.5 + CGFloat(col) * 2.4, ky, 1.8, 0.68)), with: .color(Self.kbKey))
                    }
                }
                c.fill(Path(v.r(0.5 + CGFloat(keyPhase % 6) * 2.4, 13.45 + CGFloat(keyPhase / 3) * 1.15, 1.8, 0.68)), with: .color(Self.kbHi.opacity(0.95)))
                drawBody(c, v: v, dy: bounce)
                drawPiFace(c, v: v, dy: bounce, eyeScale: blink)
            }
        }
    }

    private var alertScene: some View {
        ZStack {
            Circle()
                .fill(Self.alertC.opacity(alive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: alive)
            MascotTimeline(interval: 0.03) { t in
                let pct = t.truncatingRemainder(dividingBy: 3.5) / 3.5
                let jumpY = lerp([(0,0),(0.03,0),(0.18,-7.5),(0.26,1.3),(0.34,-5.5),(0.42,0.8),(0.5,-2.5),(0.58,0.2),(0.68,0),(1,0)], at: pct)
                let shakeX: CGFloat = (pct > 0.16 && pct < 0.56) ? sin(pct * 80) * 0.55 : 0
                let bangOp = lerp([(0,0),(0.03,1),(0.56,1),(0.64,0),(1,0)], at: pct)
                let faceColor = bangOp > 0.4 ? Self.alertC : Self.faceC
                Canvas { c, sz in
                    let v = V(sz, svgW: 16, svgH: 14, svgY0: 3)
                    drawShadow(c, v: v, width: 7 * (1.0 - abs(min(0, jumpY)) * 0.04), opacity: max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))
                    drawFeet(c, v: v, dy: jumpY)
                    c.translateBy(x: shakeX * v.s, y: 0)
                    drawBody(c, v: v, dy: jumpY)
                    drawPiFace(c, v: v, dy: jumpY, color: faceColor)
                    c.translateBy(x: -shakeX * v.s, y: 0)
                    if bangOp > 0.01 {
                        c.fill(Path(v.r(12.8, 4 + jumpY * 0.15, 1.8, 3.4)), with: .color(Self.alertC.opacity(bangOp)))
                        c.fill(Path(v.r(12.8, 8.1 + jumpY * 0.15, 1.8, 1.3)), with: .color(Self.alertC.opacity(bangOp)))
                    }
                }
            }
        }
    }
}
