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
