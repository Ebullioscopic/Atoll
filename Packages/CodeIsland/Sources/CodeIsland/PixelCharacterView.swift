import SwiftUI

/// Clawd — Claude mascot, adapted from clawd-on-desk SVG pixel art.
/// Renders SVG rects proportionally via Canvas + TimelineView animations.
struct ClawdView: View {
    let status: MascotAgentStatus
    var size: CGFloat = 27
    @State private var alive = false
    @Environment(\.mascotAnimationsActive) private var animationsActive
    @Environment(\.mascotAnimationEpoch) private var animationEpoch

    // Colors from clawd-on-desk
    private static let bodyC  = Color(red: 0.871, green: 0.533, blue: 0.427) // #DE886D
    private static let eyeC   = Color.black
    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)     // #FF3D00
    private static let kbBase = Color(red: 0.38, green: 0.44, blue: 0.50)  // lighter base
    private static let kbKey  = Color(red: 0.60, green: 0.66, blue: 0.72)  // visible keys
    private static let kbHi   = Color.white                                 // bright flash

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

    /// Legacy shim from before MascotTimeline existed — same behavior (#225),
    /// now shared with every other mascot.
    private func gatedTimeline<Content: View>(
        every interval: TimeInterval,
        staticTime: Double = 0,
        @ViewBuilder content: @escaping (Double) -> Content
    ) -> some View {
        MascotTimeline(interval: interval, staticTime: staticTime, content: content)
    }

    // ── Coordinate helper: maps SVG units to view points ──
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

    // ── Rotated arm: returns polygon path for a rect rotated around pivot ──
    private func armPath(_ v: V, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                         pivotX: CGFloat, pivotY: CGFloat, angle: CGFloat, dy: CGFloat) -> Path {
        let a = angle * .pi / 180
        let ca = cos(a), sa = sin(a)
        let corners: [(CGFloat, CGFloat)] = [
            (x - pivotX, y - pivotY),
            (x + w - pivotX, y - pivotY),
            (x + w - pivotX, y + h - pivotY),
            (x - pivotX, y + h - pivotY),
        ]
        var path = Path()
        for (i, (cx, cy)) in corners.enumerated() {
            let rx = cx * ca - cy * sa + pivotX
            let ry = cx * sa + cy * ca + pivotY
            let pt = CGPoint(x: v.ox + rx * v.s, y: v.oy + (ry - v.y0 + dy) * v.s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // Draw sleeping character (sploot pose from clawd-sleeping.svg)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private func drawSleeping(_ ctx: GraphicsContext, v: V, breathe: CGFloat, t: Double) {
        // Shadow (wider for sploot, pulses with breath)
        let shadowScale: CGFloat = 1.0 + breathe * 0.03
        ctx.fill(Path(v.r(-1, 15, 17 * shadowScale, 1)),
                 with: .color(.black.opacity(0.35 + breathe * 0.08)))

        // Legs pointing up from behind. One leg occasionally twitches in its
        // sleep — the classic dreaming-pet kick (#15). Deterministic quirk:
        // at most one twitch per ~6s cycle, sometimes skipped entirely.
        let twitch = MascotMotion.quirk(t, cycle: 6.0, duration: 0.55, seed: 0xC1A)
        let twitchLeg = MascotMotion.quirkVariant(t, cycle: 6.0, count: 4, seed: 0xC1A)
        for (i, x) in ([3, 5, 9, 11] as [CGFloat]).enumerated() {
            let kick: CGFloat = i == twitchLeg ? twitch * 0.9 : 0
            ctx.fill(Path(v.r(x, 8.5 - kick, 1, 1.5 + kick)), with: .color(Self.bodyC))
        }

        // Flattened torso — big puff on inhale (25% from SVG)
        let puff = max(0, breathe) * 0.25
        let torsoH: CGFloat = 5 * (1.0 + puff)
        let torsoY: CGFloat = 15 - torsoH
        let torsoW: CGFloat = 13 * (1.0 + breathe * 0.015) // slight width pulse
        let torsoX: CGFloat = 1 - (torsoW - 13) / 2
        ctx.fill(Path(v.r(torsoX, torsoY, torsoW, torsoH)), with: .color(Self.bodyC))

        // Arms spread flat on the ground
        ctx.fill(Path(v.r(-1, 13, 2, 2)), with: .color(Self.bodyC))
        ctx.fill(Path(v.r(14, 13, 2, 2)), with: .color(Self.bodyC))

        // Shut eyes (thicker for visibility, move with puff). A rare REM
        // flutter narrows them for a beat — dreaming, not just parked.
        let rem = MascotMotion.quirk(t, cycle: 9.0, duration: 0.7, seed: 0x5EE)
        let eyeH: CGFloat = 1.0 - rem * 0.5
        let eyeY: CGFloat = 12.2 - puff * 2.5 + (1.0 - eyeH) / 2
        ctx.fill(Path(v.r(3, eyeY, 2.5, eyeH)), with: .color(Self.eyeC))
        ctx.fill(Path(v.r(9.5, eyeY, 2.5, eyeH)), with: .color(Self.eyeC))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // SLEEP — sploot pose, breathing, floating z's
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var sleepScene: some View {
        ZStack {
            // Character body (behind) — 8fps: breathing/blinking needs no more,
            // and the idle panel is the always-visible steady state (#14 heat).
            gatedTimeline(every: 0.12) { t in
                sleepCanvas(t: t)
            }

            // Z's — continuous float-up loop, staggered timing
            gatedTimeline(every: 0.12) { t in
                floatingZs(t: t)
            }
        }
    }

    private func floatingZs(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                floatingZ(t: t, index: i)
            }
        }
    }

    private func floatingZ(t: Double, index: Int) -> some View {
        let ci = Double(index)
        let cycle = 2.8 + ci * 0.3
        let delay = ci * 0.9
        let phase = ((t - delay).truncatingRemainder(dividingBy: cycle)) / cycle
        let p = max(0, phase)
        let fontSize = max(6, size * CGFloat(0.18 + p * 0.10))
        let baseOpacity = 0.7 - ci * 0.1
        let opacity = p < 0.8 ? baseOpacity : (1.0 - p) * 3.5 * baseOpacity
        let xOff = size * CGFloat(0.08 + ci * 0.06 + sin(p * .pi * 2) * 0.03)
        let yOff = -size * CGFloat(0.15 + p * 0.38)
        return Text("z")
            .font(.system(size: fontSize, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(opacity))
            .offset(x: xOff, y: yOff)
    }

    private func sleepCanvas(t: Double) -> some View {
        // Asymmetric breath (quick inhale, slow exhale, rest) reads far more
        // alive than the old symmetric sin pulse.
        let breathe = MascotMotion.breathe(t, period: 4.5)

        return Canvas { c, sz in
            let v = V(sz, svgW: 17, svgH: 7, svgY0: 9)
            drawSleeping(c, v: v, breathe: breathe, t: t)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // WORK — typing: bounce + arm rotation + keyboard + squinted eyes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var workScene: some View {
        gatedTimeline(every: 0.03) { t in
            workCanvas(t: t)
        }
    }

    private func workCanvas(t: Double) -> some View {
        // Thinking pause: every ~11s Clawd stops typing for a beat, hands
        // hovering, eyes drifting up — bursts feel intentional, not looped (#15).
        let pause = MascotMotion.quirk(t, cycle: 11.0, duration: 1.4, seed: 0x7A9)
        let typingIntensity = 1.0 - Double(pause)

        // Body bounce softens to a breath-sway while pausing.
        let bounce = sin(t * 2 * .pi / 0.35) * 1.2 * typingIntensity
            + sin(t * 2 * .pi / 2.8) * 0.35 * (1 - typingIntensity)
        let breathe = sin(t * 2 * .pi / 3.2)

        // Arm typing with humanized cadence: strokes occasionally skip
        // (bursts and micro-pauses), and both arms lift while thinking.
        let strokeL = MascotMotion.typingStroke(t, cadence: 0.15, seed: 0x1EF7)
        let strokeR = MascotMotion.typingStroke(t, cadence: 0.12, seed: 0x819)
        let armLRaw = (strokeL.active ? sin(t * 2 * .pi / 0.15) : -0.6) * typingIntensity
        let armRRaw = (strokeR.active ? sin(t * 2 * .pi / 0.12) : -0.6) * typingIntensity
        let armL = armLRaw * 22.5 - 32.5        // -55 to -10
        let armR = armRRaw * 22.5 + 32.5        // 10 to 55

        // Key flash only on real strokes.
        let leftHit = strokeL.active && armLRaw > 0.3
        let rightHit = strokeR.active && armRRaw > 0.3
        // Vary which key lights per stroke slot (deterministic).
        let leftKeyCol = Int(MascotMotion.hash01(strokeL.slot, seed: 0xFACE0) * 3)
        let rightKeyCol = 3 + Int(MascotMotion.hash01(strokeR.slot, seed: 0xFACE1) * 3)

        // Eyes: squinted while typing; look up during the thinking pause or
        // the occasional screen-scan; natural blink cadence on top.
        let scanPhase = t.truncatingRemainder(dividingBy: 10.0)
        let scanning = scanPhase > 5.7 && scanPhase < 6.9
        let eyeScale: CGFloat = (scanning || pause > 0.3) ? 1.0 : 0.5
        let eyeDY: CGFloat = eyeScale < 0.8 ? 1.0 : -0.5
        let finalEyeScale = eyeScale * max(0.1, MascotMotion.blink(t, seed: 0xB1))

        return Canvas { c, sz in
            let v = V(sz, svgW: 16, svgH: 11, svgY0: 5.5)
            let dy = bounce

            // 1. Shadow
            let shadowW: CGFloat = 9 - abs(dy) * 0.3
            c.fill(Path(v.r(3 + (9 - shadowW) / 2, 15, shadowW, 1)),
                   with: .color(.black.opacity(max(0.1, 0.4 - abs(dy) * 0.03))))

            // 2. Short legs (h=2, behind keyboard)
            for x: CGFloat in [3, 5, 9, 11] {
                c.fill(Path(v.r(x, 13, 1, 2)), with: .color(Self.bodyC))
            }

            // 3. Torso
            let bScale = 1.0 + breathe * 0.015
            let torsoW = 11 * bScale
            c.fill(Path(v.r(2 - (torsoW - 11) / 2, 6, torsoW, 7, dy: dy)),
                   with: .color(Self.bodyC))

            // 4. Eyes
            let eyeH: CGFloat = 2 * finalEyeScale
            let eyeY: CGFloat = 8 + (2 - eyeH) / 2 + eyeDY
            c.fill(Path(v.r(4, eyeY, 1, eyeH, dy: dy)), with: .color(Self.eyeC))
            c.fill(Path(v.r(10, eyeY, 1, eyeH, dy: dy)), with: .color(Self.eyeC))

            // 5. Keyboard (on top of legs)
            c.fill(Path(v.r(-0.5, 11.8, 16, 3.5)), with: .color(Self.kbBase))
            // Key grid: 6 columns × 3 rows
            for row in 0..<3 {
                let ky = 12.2 + CGFloat(row) * 1.0
                for col in 0..<6 {
                    let kx = 0.3 + CGFloat(col) * 2.5
                    let w: CGFloat = (col == 2 && row == 1) ? 4.5 : 2.0
                    c.fill(Path(v.r(kx, ky, w, 0.7)), with: .color(Self.kbKey))
                }
            }
            // Key flashes synced with arm hits
            if leftHit {
                let row = leftKeyCol % 3
                let kx = 0.3 + CGFloat(leftKeyCol) * 2.5
                let ky = 12.2 + CGFloat(row) * 1.0
                c.fill(Path(v.r(kx, ky, 2.0, 0.7)), with: .color(Self.kbHi.opacity(0.9)))
            }
            if rightHit {
                let row = (rightKeyCol - 3) % 3
                let kx = 0.3 + CGFloat(rightKeyCol) * 2.5
                let ky = 12.2 + CGFloat(row) * 1.0
                c.fill(Path(v.r(kx, ky, 2.0, 0.7)), with: .color(Self.kbHi.opacity(0.9)))
            }

            // 6. Arms on top — pivot at body connection (inner edge of arm)
            c.fill(armPath(v, x: 0, y: 9, w: 2, h: 2, pivotX: 2, pivotY: 10,
                           angle: armL, dy: dy), with: .color(Self.bodyC))
            c.fill(armPath(v, x: 13, y: 9, w: 2, h: 2, pivotX: 13, pivotY: 10,
                           angle: armR, dy: dy), with: .color(Self.bodyC))
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ALERT — 3.5s cycle: startle → decaying jumps → rest
    // Matches clawd-notification.svg keyframes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    private var alertScene: some View {
        // The pulsing glow uses a `.repeatForever` CAAnimation that misbehaves
        // across display wake (#225). Only let it run while animations are
        // active; otherwise hold a static frame so it can't pin a core.
        let glowActive = alive && animationsActive
        return ZStack {
            Circle()
                .fill(Self.alertC.opacity(glowActive ? 0.12 : 0))
                .frame(width: size * 0.8)
                .blur(radius: size * 0.05)
                .animation(
                    animationsActive
                        ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                        : .default,
                    value: glowActive
                )
                .id(animationEpoch)

            gatedTimeline(every: 0.03) { t in
                alertCanvas(t: t)
            }
        }
    }

    // Interpolate between keyframes: [(pct, value)]
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

    private func alertCanvas(t: Double) -> some View {
        let cycle = t.truncatingRemainder(dividingBy: 3.5)
        let pct = cycle / 3.5

        // Body jump — smooth interpolation from SVG keyframes
        let jumpY = lerp([
            (0, 0), (0.03, 0), (0.10, -1), (0.15, 1.5),
            (0.175, -10), (0.20, -10), (0.25, 1.5),
            (0.275, -8), (0.30, -8), (0.35, 1.2),
            (0.375, -5), (0.40, -5), (0.45, 1.0),
            (0.475, -3), (0.50, -3), (0.55, 0.5),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        // Squash/stretch on landing (exaggerated for visibility)
        let scaleX: CGFloat = jumpY > 0.5 ? 1.0 + jumpY * 0.05 : 1.0  // squash wider
        let scaleY: CGFloat = jumpY > 0.5 ? 1.0 - jumpY * 0.04 : 1.0  // squash shorter

        // Arm waving — smooth interpolation
        let armL = lerp([
            (0, 0), (0.03, 0), (0.10, 25),
            (0.15, 30), (0.20, 155), (0.25, 115),
            (0.30, 140), (0.35, 100), (0.40, 115),
            (0.45, 80), (0.50, 80), (0.55, 40),
            (0.62, 0), (1.0, 0),
        ], at: pct)
        let armR = -lerp([
            (0, 0), (0.03, 0), (0.10, 30),
            (0.15, 30), (0.20, 155), (0.25, 115),
            (0.30, 140), (0.35, 100), (0.40, 115),
            (0.45, 80), (0.50, 80), (0.55, 40),
            (0.62, 0), (1.0, 0),
        ], at: pct)

        // Eye startle: widen + shift gaze on initial startle
        let eyeScale: CGFloat = (pct > 0.03 && pct < 0.15) ? 1.3 : 1.0
        let eyeDY: CGFloat = (pct > 0.03 && pct < 0.15) ? -0.5 : 0

        // ! mark
        let bangOpacity = lerp([
            (0, 0), (0.03, 1), (0.10, 1), (0.55, 1), (0.62, 0), (1.0, 0),
        ], at: pct)
        let bangScale = lerp([
            (0, 0.3), (0.03, 1.3), (0.10, 1.0), (0.55, 1.0), (0.62, 0.6), (1.0, 0.6),
        ], at: pct)

        return Canvas { c, sz in
            // Taller viewport to fit ! mark above head
            let v = V(sz, svgW: 15, svgH: 12, svgY0: 4)

            // Shadow — reacts to jump height
            let shadowW: CGFloat = 9 * (1.0 - abs(min(0, jumpY)) * 0.04)
            let shadowOp = max(0.08, 0.5 - abs(min(0, jumpY)) * 0.04)
            c.fill(Path(v.r(3 + (9 - shadowW) / 2, 15, shadowW, 1)),
                   with: .color(.black.opacity(shadowOp)))

            // Legs
            for x: CGFloat in [3, 5, 9, 11] {
                c.fill(Path(v.r(x, 11, 1, 4)), with: .color(Self.bodyC))
            }

            // Torso with squash/stretch
            let torsoW = 11 * scaleX
            let torsoH = 7 * scaleY
            let torsoX = 2 - (torsoW - 11) / 2
            let torsoY = 6 + (7 - torsoH)  // stretch from bottom
            c.fill(Path(v.r(torsoX, torsoY, torsoW, torsoH, dy: jumpY)),
                   with: .color(Self.bodyC))

            // Eyes (startled = wider)
            let eyeH = 2 * eyeScale
            let eyeYPos = 8 + (2 - eyeH) / 2 + eyeDY
            c.fill(Path(v.r(4, eyeYPos, 1, eyeH, dy: jumpY)), with: .color(Self.eyeC))
            c.fill(Path(v.r(10, eyeYPos, 1, eyeH, dy: jumpY)), with: .color(Self.eyeC))

            // Arms — correct pivot at body connection
            c.fill(armPath(v, x: 0, y: 9, w: 2, h: 2, pivotX: 2, pivotY: 10,
                           angle: armL, dy: jumpY), with: .color(Self.bodyC))
            c.fill(armPath(v, x: 13, y: 9, w: 2, h: 2, pivotX: 13, pivotY: 10,
                           angle: armR, dy: jumpY), with: .color(Self.bodyC))

            // ! mark — positioned above head, dampened movement (doesn't fly off screen)
            if bangOpacity > 0.01 {
                let bw: CGFloat = 2 * bangScale
                let bx: CGFloat = 13
                let by: CGFloat = 4.5 + jumpY * 0.15 // dampened: only 15% of jump
                c.fill(Path(v.r(bx, by, bw, 3.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOpacity)))
                c.fill(Path(v.r(bx, by + 4.0 * bangScale, bw, 1.5 * bangScale, dy: 0)),
                       with: .color(Self.alertC.opacity(bangOpacity)))
            }
        }
    }
}
