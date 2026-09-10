import AppKit
import SwiftUI

private struct ChatTextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1
}
extension EnvironmentValues {
    var chatTextScale: Double {
        get { self[ChatTextScaleKey.self] }
        set { self[ChatTextScaleKey.self] = newValue }
    }
}

/// Drop-in body for MarkdownText: ChatMarkdownView(content: content).
/// Parsing in init also keeps body re-evaluation from reparsing unchanged input.
struct ChatMarkdownView: View {
    @Environment(\.chatTextScale) private var textScale
    private let blocks: [ChatMarkdown.Block]

    init(content: String) {
        blocks = ChatMarkdown.parse(content)
    }

    var body: some View {
        ChatMarkdownBlocksView(blocks: blocks)
            .font(.system(size: 14 * textScale))
            .foregroundStyle(.primary)
            .tint(.accentColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                ChatMarkdown.isSafeLink(url) ? .systemAction : .discarded
            })
    }
}

private struct ChatMarkdownBlocksView: View {
    let blocks: [ChatMarkdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                ChatMarkdownBlockView(block: blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMarkdownInlineView: View {
    let content: String

    var body: some View {
        Text(ChatMarkdown.inline(content))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMarkdownBlockView: View {
    @Environment(\.chatTextScale) private var textScale
    let block: ChatMarkdown.Block

    @ViewBuilder var body: some View {
        switch block {
        case let .heading(level, text):
            ChatMarkdownInlineView(content: text)
                .font(.system(size: headingSize(level) * textScale, weight: .semibold))
                .padding(.top, 3)
                .accessibilityAddTraits(.isHeader)
        case let .paragraph(text):
            ChatMarkdownInlineView(content: text)
        case let .list(items):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: items[index].marker)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 16, alignment: .trailing)
                            .fixedSize()
                        // Type erasure bounds the recursive view's generic type.
                        AnyView(ChatMarkdownBlocksView(blocks: items[index].blocks))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .quote(blocks):
            AnyView(ChatMarkdownBlocksView(blocks: blocks))
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
                .padding(.vertical, 3)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 3)
                }
        case let .code(language, content, _):
            ChatMarkdownCodeView(language: language, content: content)
        case let .table(table):
            ChatMarkdownTableView(table: table)
        case .rule:
            Divider().padding(.vertical, 3)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 23
        case 2: return 20
        case 3: return 17
        default: return 15
        }
    }
}

private struct ChatMarkdownCodeView: View {
    @Environment(\.chatTextScale) private var textScale
    let language: String?
    let content: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: language ?? "代码")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(content, forType: .string)
                } label: {
                    Label(copied ? "已复制" : "复制代码", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("复制代码")
                .accessibilityLabel(copied ? "代码已复制" : "复制代码")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            Divider().opacity(0.5)
            ScrollView(.horizontal) {
                Text(verbatim: content.isEmpty ? " " : content)
                    .font(.system(size: 12.5 * textScale, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07)) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: content) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                copied = false
            } catch { /* View disappeared or streaming content changed. */ }
        }
    }
}

private struct ChatMarkdownTableView: View {
    @Environment(\.chatTextScale) private var textScale
    let table: ChatMarkdown.Table
    private let cellWidth: CGFloat = 156

    var body: some View {
        // Only the scroll content has an intrinsic wide size; the viewport takes
        // the chat bubble's proposal, including the narrower padded user bubble.
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                row(table.headers, header: true, alternate: false)
                ForEach(table.rows.indices, id: \.self) { index in
                    row(table.rows[index], header: false, alternate: index.isMultiple(of: 2))
                }
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.09)) }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ cells: [String], header: Bool, alternate: Bool) -> some View {
        GridRow(alignment: .top) {
            ForEach(table.headers.indices, id: \.self) { index in
                Text(ChatMarkdown.inline(index < cells.count ? cells[index] : ""))
                    .font(.system(size: 13 * textScale, weight: header ? .semibold : .regular))
                    .lineSpacing(3)
                    .multilineTextAlignment(textAlignment(table.alignments[index]))
                    .frame(width: cellWidth, alignment: alignment(table.alignments[index]))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.primary.opacity(header ? 0.065 : (alternate ? 0.025 : 0)))
                    .overlay(alignment: .bottom) { Divider().opacity(0.4) }
            }
        }
    }

    private func alignment(_ value: ChatMarkdown.Table.Alignment) -> Alignment {
        switch value {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ value: ChatMarkdown.Table.Alignment) -> TextAlignment {
        switch value {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
