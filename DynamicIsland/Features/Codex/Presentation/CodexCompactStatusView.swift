import SwiftUI

struct CodexCompactStatusView: View {
  let status: CodexCompactStatus
  let availableWidth: CGFloat
  let availableHeight: CGFloat

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      ForEach(Array(status.lines.enumerated()), id: \.offset) { _, line in
        MarqueeText(
          .constant(line.displayText),
          font: .system(size: fontSize, weight: .semibold),
          nsFont: .body,
          textColor: line.tone.swiftUIColor,
          minDuration: 1,
          frameWidth: availableWidth
        )
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

  private var fontSize: CGFloat {
    switch status.lines.count {
    case 0...1: return 10.5
    case 2: return 9
    default: return 7.5
    }
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
