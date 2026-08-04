import SwiftUI

/// DroidBot — Factory/Droid mascot, pixel-art industrial robot.
/// Rust orange #D56A26 on warm brown-black #161413. Mechanical/factory aesthetic.
struct DroidView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false

    // Factory brand palette — warm industrial
    private static let bodyC   = Color(red: 0.835, green: 0.416, blue: 0.149) // #D56A26 rust orange
    private static let bodyDk  = Color(red: 0.65, green: 0.32, blue: 0.12)    // darker orange
    private static let metalC  = Color(red: 0.40, green: 0.37, blue: 0.34)    // metal gray
    private static let eyeC    = Color(red: 0.89, green: 0.60, blue: 0.16)    // #E3992A gold
    private static let alertC  = Color(red: 1.0, green: 0.24, blue: 0.0)
    private static let kbBase  = Color(red: 0.15, green: 0.13, blue: 0.12)
    private static let kbKey   = Color(red: 0.32, green: 0.28, blue: 0.25)
    private static let kbHi    = Color(red: 0.835, green: 0.416, blue: 0.149)

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

    // ── Draw robot body — boxy industrial droid ──
    private func drawRobot(_ c: GraphicsContext, v: V, dy: CGFloat,
                           squashX: CGFloat = 1, squashY: CGFloat = 1) {
        let cx: CGFloat = 7.5

        // Main body (box)
        let bw: CGFloat = 9 * squashX, bh: CGFloat = 6 * squashY
        let bx = cx - bw / 2
        let by: CGFloat = 9 + (6 - bh)
        c.fill(Path(v.r(bx, by, bw, bh, dy: dy)), with: .color(Self.bodyC))

        // Head (smaller box on top)
        let hw: CGFloat = 7 * squashX, hh: CGFloat = 3 * squashY
        let hx = cx - hw / 2
        let hy = by - hh + 0.5
        c.fill(Path(v.r(hx, hy, hw, hh, dy: dy)), with: .color(Self.bodyC))

        // Antenna
        let ax = cx - 0.5
        c.fill(Path(v.r(ax, hy - 2, 1, 2, dy: dy)), with: .color(Self.metalC))
        c.fill(Path(v.r(ax - 0.5, hy - 2.5, 2, 1, dy: dy)), with: .color(Self.eyeC))

        // Chest plate (darker inner rectangle)
        let pw: CGFloat = 5 * squashX, ph: CGFloat = 3 * squashY
        c.fill(Path(v.r(cx - pw / 2, by + 1, pw, ph, dy: dy)), with: .color(Self.bodyDk))

        // Rivets / bolts on chest (pixel dots)
        c.fill(Path(v.r(cx - pw / 2 + 0.5, by + 1.5, 0.8, 0.8, dy: dy)),
               with: .color(Self.metalC))
        c.fill(Path(v.r(cx + pw / 2 - 1.3, by + 1.5, 0.8, 0.8, dy: dy)),
               with: .color(Self.metalC))

        // Arms (rectangles on sides)
        c.fill(Path(v.r(bx - 1.5, by + 1, 1.5, 4 * squashY, dy: dy)),
               with: .color(Self.metalC))
        c.fill(Path(v.r(bx + bw, by + 1, 1.5, 4 * squashY, dy: dy)),
               with: .color(Self.metalC))
    }

    // ── Draw robot eyes — glowing rectangles ──
    private func drawEyes(_ c: GraphicsContext, v: V, dy: CGFloat,
                          color: Color = Self.eyeC, scale: CGFloat = 1.0) {
        let eyeW: CGFloat = 1.5, eyeH: CGFloat = 1.2 * scale
        let eyeY: CGFloat = 8.0 + (1.2 - eyeH) / 2
        c.fill(Path(v.r(4.8, eyeY, eyeW, max(0.2, eyeH), dy: dy)), with: .color(color))
        c.fill(Path(v.r(8.7, eyeY, eyeW, max(0.2, eyeH), dy: dy)), with: .color(color))
    }

    private func drawShadow(_ c: GraphicsContext, v: V, width: CGFloat = 9, opacity: Double = 0.3) {
        c.fill(Path(v.r(7.5 - width / 2, 16, width, 1)),
               with: .color(.black.opacity(opacity)))
    }

    private func drawLegs(_ c: GraphicsContext, v: V) {
        // Blocky robot feet
        c.fill(Path(v.r(4.5, 14.5, 2, 1.5)), with: .color(Self.metalC))
        c.fill(Path(v.r(8.5, 14.5, 2, 1.5)), with: .color(Self.metalC))
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
        let phase = t.truncatingRemainder(dividingBy: 5.0) / 5.0
        // Slow breathing — mechanical rhythm
        let breathe = sin(phase * .pi * 2) * 0.4
        // Eye dim flicker (like powering down)
        let eyeFlicker = t.truncatingRemainder(dividingBy: 3.0)
        let eyeOn = eyeFlicker < 2.5

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 16, svgY0: 2)
            drawShadow(c, v: v, width: 8, opacity: 0.2)
            drawLegs(c, v: v)
            drawRobot(c, v: v, dy: breathe)
            if eyeOn {
                drawEyes(c, v: v, dy: breathe, color: Self.eyeC.opacity(0.3), scale: 0.4)
            }
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
        let workPause = MascotMotion.quirk(t, cycle: 10.6, duration: 1.2, seed: 0x296)
        let bounce = sin(t * 2 * .pi / 0.5) * 0.8 * (1 - workPause)
            + sin(t * 2 * .pi / 2.9) * 0.3 * workPause
        let blink = max(0.1, MascotMotion.blink(t, seed: 0x297))
        let keyPhase = Int(t / 0.12) % 6  // slightly slower typing

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 16, svgY0: 2)

            let shadowW: CGFloat = 9 - abs(bounce) * 0.3
            c.fill(Path(v.r(3.5 + (9 - shadowW) / 2, 17, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.35 - abs(bounce) * 0.03))))

            drawLegs(c, v: v)

            // Keyboard
            c.fill(Path(v.r(0, 15, 15, 3)), with: .color(Self.kbBase))
            for row in 0..<2 {
                let ky = 15.5 + CGFloat(row) * 1.2
                for col in 0..<6 {
                    let kx = 0.5 + CGFloat(col) * 2.4
                    c.fill(Path(v.r(kx, ky, 1.8, 0.7)), with: .color(Self.kbKey))
                }
            }
            let fCol = keyPhase % 6
            let fRow = keyPhase / 3
            c.fill(Path(v.r(0.5 + CGFloat(fCol) * 2.4, 15.5 + CGFloat(fRow) * 1.2, 1.8, 0.7)),
                   with: .color(Self.kbHi.opacity(0.9)))

            drawRobot(c, v: v, dy: bounce)
            drawEyes(c, v: v, dy: bounce, scale: blink)
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

        // Eyes flash red during alert
        let eyeFlash = (pct > 0.03 && pct < 0.55 && sin(pct * 20) > 0)
        let eyeColor = eyeFlash ? Self.alertC : Self.eyeC

        let bangOp = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 16, svgY0: 2)

            let shadowW: CGFloat = 9 * (1.0 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(3.5 + (9 - shadowW) / 2, 17, shadowW, 1)),
                   with: .color(.black.opacity(max(0.08, 0.4 - abs(min(0, jumpY)) * 0.04))))

            drawLegs(c, v: v)

            c.translateBy(x: shakeX * v.s, y: 0)
            drawRobot(c, v: v, dy: jumpY, squashX: squashX, squashY: squashY)
            drawEyes(c, v: v, dy: jumpY, color: eyeColor,
                     scale: pct > 0.03 && pct < 0.15 ? 1.3 : 1.0)
            c.translateBy(x: -shakeX * v.s, y: 0)

            if bangOp > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 13
                let by: CGFloat = 3 + jumpY * 0.15
                c.fill(Path(v.r(bx, by, bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale, bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOp)))
            }
        }
    }
}
