import SwiftUI

struct CodexCompactStatusView: View {
  let status: CodexCompactStatus
  let availableWidth: CGFloat
  let availableHeight: CGFloat

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      ForEach(Array(status.lines.enumerated()), id: \.offset) { _, line in
        Text(line.displayText)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(line.tone.swiftUIColor)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
          .frame(width: availableWidth, height: rowHeight, alignment: .trailing)
      }
    }
    .frame(width: availableWidth, height: availableHeight, alignment: .center)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(status.lines.map(\.displayText).joined(separator: "，"))
  }

  private var rowHeight: CGFloat {
    availableHeight / CGFloat(max(status.lines.count, 1))
  }
}

extension CodexCompactStatusTone {
  var swiftUIColor: Color {
    switch self {
    case .blue: return .blue
    case .green: return .green
    case .orange: return .orange
    }
  }
}

struct CodexBusyIconView: View {
  let accent: Color
  let size: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      Canvas { context, canvasSize in
        drawIcon(
          in: context,
          canvasSize: canvasSize,
          elapsed: reduceMotion ? 0.72 : timeline.date.timeIntervalSinceReferenceDate
        )
      }
    }
    .frame(width: size, height: size)
    .shadow(color: accent.opacity(0.22), radius: max(1.5, size * 0.08))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Codex 正在运行")
  }

  private func drawIcon(
    in context: GraphicsContext,
    canvasSize: CGSize,
    elapsed: TimeInterval
  ) {
    let side = min(canvasSize.width, canvasSize.height)
    let tileWidth = side
    let tileHeight = side * 0.78
    let tileRect = CGRect(
      x: (canvasSize.width - tileWidth) / 2,
      y: (canvasSize.height - tileHeight) / 2,
      width: tileWidth,
      height: tileHeight
    )
    let cornerRadius = max(4, side * 0.17)
    let tilePath = Path(roundedRect: tileRect, cornerRadius: cornerRadius)
    let breath = (sin(elapsed * .pi / 1.4) + 1) / 2
    let signalColor = Color(red: 0.62, green: 0.86, blue: 1)

    context.fill(
      tilePath,
      with: .linearGradient(
        Gradient(colors: [
          Color(red: 0.015, green: 0.06, blue: 0.14).opacity(0.98),
          accent.opacity(0.34 + breath * 0.08),
        ]),
        startPoint: CGPoint(x: tileRect.minX, y: tileRect.minY),
        endPoint: CGPoint(x: tileRect.maxX, y: tileRect.maxY)
      )
    )
    context.stroke(
      tilePath,
      with: .color(accent.opacity(0.58 + breath * 0.12)),
      lineWidth: max(0.6, side * 0.025)
    )

    let promptCenterY = tileRect.midY
    let promptX = tileRect.minX + side * 0.2
    let promptRadius = side * 0.09
    var prompt = Path()
    prompt.move(to: CGPoint(x: promptX, y: promptCenterY - promptRadius))
    prompt.addLine(to: CGPoint(x: promptX + promptRadius, y: promptCenterY))
    prompt.addLine(to: CGPoint(x: promptX, y: promptCenterY + promptRadius))
    context.stroke(
      prompt,
      with: .color(signalColor.opacity(0.96)),
      style: StrokeStyle(
        lineWidth: max(1.2, side * 0.055),
        lineCap: .round,
        lineJoin: .round
      )
    )

    let cycle = elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8
    let activeLine = cycle < 0.52 ? 0 : 1
    let localCycle = activeLine == 0 ? cycle / 0.52 : (cycle - 0.52) / 0.48
    let progress = easeOutCubic(min(max(localCycle, 0), 1))
    let lineHeight = max(1.2, side * 0.052)
    let lineX = tileRect.minX + side * 0.4
    let lineYs = [tileRect.minY + tileHeight * 0.38, tileRect.minY + tileHeight * 0.64]
    let lineWidths = [side * 0.34, side * 0.43]

    for index in 0..<2 {
      let baselineRect = CGRect(
        x: lineX,
        y: lineYs[index] - lineHeight / 2,
        width: lineWidths[index],
        height: lineHeight
      )
      context.fill(
        Path(roundedRect: baselineRect, cornerRadius: lineHeight / 2),
        with: .color(.white.opacity(index == activeLine ? 0.22 : 0.34))
      )

      guard index == activeLine else { continue }
      let activeWidth = max(lineHeight, lineWidths[index] * progress)
      let activeRect = CGRect(
        x: lineX,
        y: lineYs[index] - lineHeight / 2,
        width: activeWidth,
        height: lineHeight
      )
      context.fill(
        Path(roundedRect: activeRect, cornerRadius: lineHeight / 2),
        with: .color(signalColor.opacity(0.92))
      )

      let cursorOpacity = 0.48 + 0.48 * ((sin(elapsed * .pi * 3.2) + 1) / 2)
      let cursorRect = CGRect(
        x: min(lineX + activeWidth + side * 0.035, tileRect.maxX - side * 0.13),
        y: lineYs[index] - side * 0.085,
        width: max(1, side * 0.035),
        height: side * 0.17
      )
      context.fill(
        Path(roundedRect: cursorRect, cornerRadius: cursorRect.width / 2),
        with: .color(.white.opacity(cursorOpacity))
      )
    }
  }

  private func easeOutCubic(_ value: Double) -> Double {
    1 - pow(1 - value, 3)
  }
}

struct CodexSneakPeekView: View {
  let title: String
  let subtitle: String
  let isCompletionPulse: Bool
  let isRunningPulse: Bool
  let isWaitingForApproval: Bool
  let accent: Color
  let availableWidth: CGFloat

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false
  @State private var pulseProgress: CGFloat = 0
  @State private var pulseOpacity = 0.0

  var body: some View {
    HStack(spacing: isCompletionPulse ? 9 : 7) {
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [accent.opacity(isCompletionPulse ? 0.30 : 0.12), accent.opacity(0.04)],
              center: .center,
              startRadius: 0,
              endRadius: isCompletionPulse ? 15 : 10
            )
          )

        if !reduceMotion, isCompletionPulse {
          Circle()
            .trim(from: 0.08, to: 0.92)
            .stroke(
              AngularGradient(
                colors: [accent.opacity(0.08), accent, accent.opacity(0.08)],
                center: .center
              ),
              style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            .rotationEffect(.degrees(-90 + Double(pulseProgress) * 110))
            .scaleEffect(0.72 + pulseProgress * 0.68)
            .opacity(pulseOpacity)

          ForEach(Array(sparkAngles.enumerated()), id: \.offset) { _, angle in
            let radians = angle * .pi / 180
            let distance = 10 + pulseProgress * 7
            Circle()
              .fill(accent)
              .frame(width: 2.6, height: 2.6)
              .offset(
                x: CGFloat(cos(radians)) * distance,
                y: CGFloat(sin(radians)) * distance
              )
              .scaleEffect(0.7 + CGFloat(sparkOpacity) * 0.45)
              .opacity(sparkOpacity)
          }
        } else if !reduceMotion {
          Circle()
            .stroke(accent.opacity(pulseOpacity), lineWidth: 1)
            .scaleEffect(0.72 + pulseProgress * 0.48)
        }

        Image(systemName: symbolName)
          .font(.system(size: isCompletionPulse ? 13 : 10, weight: .bold))
          .foregroundStyle(accent)
          .scaleEffect(isCompletionPulse && !reduceMotion ? 0.88 + pulseProgress * 0.12 : 1)
      }
      .frame(width: isCompletionPulse ? 26 : 18, height: isCompletionPulse ? 26 : 18)
      .shadow(
        color: accent.opacity(isCompletionPulse ? 0.34 : 0.12),
        radius: isCompletionPulse ? 8 : 2
      )

      if isCompletionPulse {
        completionContent
      } else if isRunningPulse {
        runningContent
      } else {
        Text(displayText)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.86))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(width: availableWidth, alignment: .leading)
    .offset(y: appeared ? 0 : 3)
    .scaleEffect(appeared ? 1 : 0.97, anchor: .leading)
    .opacity(appeared ? 1 : 0)
    .blur(radius: appeared ? 0 : 2.5)
    .onAppear {
      withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: reduceMotion ? 0.12 : 0.42)) {
        appeared = true
      }
    }
    .task {
      guard !reduceMotion else { return }
      pulseProgress = 0
      pulseOpacity = isCompletionPulse ? 0.78 : 0.42
      withAnimation(.easeOut(duration: isCompletionPulse ? 0.72 : 0.58)) {
        pulseProgress = 1
      }
      try? await Task.sleep(for: .milliseconds(isCompletionPulse ? 520 : 420))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.24)) {
        pulseOpacity = 0
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var normalizedTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Codex" : trimmed
  }

  private var normalizedSubtitle: String {
    let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    return isCompletionPulse ? "对话已完成" : "开始执行新的 Codex 对话"
  }

  @ViewBuilder
  private var runningContent: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 4) {
        Circle()
          .fill(accent.opacity(0.72))
          .frame(width: 3, height: 3)

        Text(normalizedTitle)
          .font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.48))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      GeometryReader { geometry in
        MarqueeText(
          .constant(normalizedSubtitle),
          font: .system(size: 11.5, weight: .medium),
          nsFont: .caption1,
          textColor: Color.white.opacity(0.86),
          minDuration: 0.28,
          frameWidth: max(40, geometry.size.width),
          pointsPerSecond: 58
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
          LinearGradient(
            colors: [.clear, .black.opacity(0.88)],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 12)
          .allowsHitTesting(false)
        }
      }
      .frame(height: 15)
    }
    .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
  }

  @ViewBuilder
  private var completionContent: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Text(normalizedTitle)
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.58))
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer(minLength: 4)

        HStack(spacing: 3) {
          Image(systemName: "checkmark")
            .font(.system(size: 7.5, weight: .bold))
          Text("已完成")
            .font(.system(size: 8.5, weight: .bold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
          Capsule(style: .continuous)
            .fill(accent.opacity(0.14))
            .overlay(
              Capsule(style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 0.7)
            )
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      GeometryReader { geometry in
        MarqueeText(
          .constant(normalizedSubtitle),
          font: .system(size: 12.5, weight: .semibold),
          nsFont: .caption1,
          textColor: Color.white.opacity(0.92),
          minDuration: 0.34,
          frameWidth: max(40, geometry.size.width),
          pointsPerSecond: 54
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
          LinearGradient(
            colors: [.clear, .black.opacity(0.92)],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 16)
          .allowsHitTesting(false)
        }
      }
      .frame(height: 17)
    }
    .frame(maxWidth: .infinity, minHeight: 33, alignment: .leading)
  }

  private var displayText: String {
    if isCompletionPulse { return "\(normalizedTitle) · 已完成" }
    if isRunningPulse { return "\(normalizedTitle) · 正在处理" }
    if isWaitingForApproval { return "\(normalizedTitle) · 等待批准" }
    return "\(normalizedTitle) · 正在处理"
  }

  private var accessibilityText: String {
    if isCompletionPulse {
      return "项目 \(normalizedTitle)，对话 \(normalizedSubtitle)，已完成"
    }
    if isRunningPulse {
      return "项目 \(normalizedTitle)，开始执行 \(normalizedSubtitle)"
    }
    return displayText
  }

  private var symbolName: String {
    if isCompletionPulse { return "checkmark" }
    if isWaitingForApproval { return "exclamationmark" }
    return "terminal.fill"
  }

  private var sparkAngles: [Double] {
    [-145, -90, -35]
  }

  private var sparkOpacity: Double {
    max(0, sin(Double(pulseProgress) * .pi)) * 0.74
  }
}
