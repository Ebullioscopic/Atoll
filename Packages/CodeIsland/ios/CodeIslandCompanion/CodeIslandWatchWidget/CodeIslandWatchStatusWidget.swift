import SwiftUI
import WidgetKit

struct CodeIslandWatchStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CodeIslandWatchStatusWidget", provider: CodeIslandWatchTimelineProvider()) { entry in
            CodeIslandWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Code Island")
        .description(L10n.t(zh: "显示当前 Mac 会话状态。", en: "Shows the current Mac session status."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CodeIslandWatchTimelineEntry: TimelineEntry {
    let date: Date
    let state: CompanionStatePayload?
}

struct CodeIslandWatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodeIslandWatchTimelineEntry {
        CodeIslandWatchTimelineEntry(date: Date(), state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodeIslandWatchTimelineEntry) -> Void) {
        completion(CodeIslandWatchTimelineEntry(date: Date(), state: WatchStateStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodeIslandWatchTimelineEntry>) -> Void) {
        let entry = CodeIslandWatchTimelineEntry(date: Date(), state: WatchStateStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
    }
}

private struct CodeIslandWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CodeIslandWatchTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWidgetView(state: entry.state)
        case .accessoryRectangular:
            RectangularWidgetView(state: entry.state)
        case .accessoryInline:
            InlineWidgetView(state: entry.state)
        default:
            RectangularWidgetView(state: entry.state)
        }
    }
}

private struct CircularWidgetView: View {
    let state: CompanionStatePayload?

    var body: some View {
        VStack(spacing: 2) {
            SharedMascotView(source: state?.source ?? "codex", status: status, size: 24)
            Text(state?.status.shortLabel ?? L10n.t(zh: "等待", en: "Wait"))
                .font(.system(size: 10, weight: .black, design: .rounded))
                .lineLimit(1)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var status: MascotAgentStatus {
        MascotAgentStatus(state?.status.rawValue ?? "idle")
    }
}

private struct RectangularWidgetView: View {
    let state: CompanionStatePayload?

    var body: some View {
        HStack(spacing: 7) {
            SharedMascotView(source: state?.source ?? "codex", status: status, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(sourceText)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(messageText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(statusColor(state?.status ?? .idle))
                .frame(width: 8, height: 8)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var sourceText: String {
        CompanionDisplayText.source(state?.source)
    }

    private var messageText: String {
        if let question = state?.question?.question {
            return question
        }
        if let message = CompanionDisplayText.message(state?.messages.last?.text) {
            return message
        }
        return state == nil
            ? L10n.t(zh: "等待同步", en: "Waiting to sync")
            : L10n.t(zh: "当前没有新的消息", en: "No new messages")
    }

    private var status: MascotAgentStatus {
        MascotAgentStatus(state?.status.rawValue ?? "idle")
    }
}

private struct InlineWidgetView: View {
    let state: CompanionStatePayload?

    var body: some View {
        Text("\(CompanionDisplayText.source(state?.source)) \(state?.status.shortLabel ?? L10n.t(zh: "等待同步", en: "Waiting"))")
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

private func statusColor(_ status: CompanionStatus) -> Color {
    switch status {
    case .idle:
        return Color(red: 0.62, green: 0.68, blue: 0.76)
    case .processing, .running:
        return Color(red: 0.25, green: 0.86, blue: 0.38)
    case .waitingApproval, .waitingQuestion:
        return Color.orange
    }
}
