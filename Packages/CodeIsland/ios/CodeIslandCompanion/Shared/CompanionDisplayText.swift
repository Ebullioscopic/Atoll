import Foundation

enum CompanionDisplayText {
    static func source(_ text: String?) -> String {
        guard let trimmed = cleaned(text) else { return "CodeIsland" }

        switch trimmed.lowercased() {
        case "claude", "claudecode", "clawd":
            return "CLAUDE"
        case "codex", "openai":
            return "CODEX"
        case "gemini":
            return "GEMINI"
        case "cursor", "cursor-cli":
            return "CURSOR"
        case "qoder", "qoder-cli":
            return "QODER"
        case "opencode":
            return "OPENCODE"
        case "qwen":
            return "QWEN"
        default:
            return trimmed.uppercased()
        }
    }

    static func message(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed {
        case "[Request interrupted by user]", "Request interrupted by user":
            return L10n.t(zh: "请求已被你中断", en: "Request interrupted by you")
        case "[Request interrupted by user for tool use]", "Request interrupted by user for tool use":
            return L10n.t(zh: "工具调用已被你中断", en: "Tool call interrupted by you")
        default:
            return trimmed
        }
    }

    static func tool(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed.lowercased() {
        case "askuserquestion":
            return L10n.t(zh: "提问", en: "Question")
        case "bash", "shell":
            return L10n.t(zh: "终端", en: "Terminal")
        case "read":
            return L10n.t(zh: "读取", en: "Read")
        case "edit", "write", "multiedit":
            return L10n.t(zh: "编辑", en: "Edit")
        case "grep", "glob", "search":
            return L10n.t(zh: "搜索", en: "Search")
        case "webfetch", "websearch":
            return L10n.t(zh: "网页", en: "Web")
        case "todowrite":
            return L10n.t(zh: "计划", en: "Plan")
        case "notebookedit":
            return L10n.t(zh: "笔记", en: "Notebook")
        default:
            return trimmed
        }
    }

    static func workspace(_ text: String?) -> String? {
        guard let trimmed = cleaned(text) else { return nil }

        switch trimmed.lowercased() {
        case "workspace":
            return L10n.t(zh: "工作区", en: "Workspace")
        default:
            return trimmed
        }
    }

    static func subtitle(workspaceName: String?, toolName: String?, fallback: String) -> String {
        if let workspaceName = workspace(workspaceName) {
            return workspaceName
        }
        if let toolName = tool(toolName) {
            return toolName
        }
        return fallback
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static var markdownCache: [String: AttributedString] = [:]
    private static let markdownCacheLimit = 128

    /// 消息正文渲染，与 Mac notch 的 ChatMessageTextFormatter 一致：
    /// 用户消息按纯文本（不渲染 markdown，避免把输入里的符号当语法）；
    /// 助手消息先去掉 `::directive{...}` 指令块、合并多余空行，再做行内 markdown。
    static func messageMarkdown(_ text: String, isUser: Bool) -> AttributedString {
        isUser ? AttributedString(text) : inlineMarkdown(compactText(stripDirectives(text)))
    }

    /// 行内 markdown 渲染（粗体 / 斜体 / 代码 / 链接 / ``` 围栏代码块），与 Mac notch 一致。
    /// 仅用于消息正文与问题等散文内容，不要用于来源名 / 工作区 / 工具名
    /// （含下划线的路径会被误判为斜体）。
    ///
    /// 结果按文本缓存：同一段文字始终返回同一个 AttributedString，避免看板被活动会话
    /// 频繁刷新时，静止的空闲会话因重复解析出新实例而被 SwiftUI 反复重绘/动画（闪烁）。
    static func inlineMarkdown(_ text: String) -> AttributedString {
        if let cached = markdownCache[text] {
            return cached
        }
        let result = text.contains("```")
            ? renderWithFencedCodeBlocks(text)
            : renderInlineOnly(text)
        if markdownCache.count >= markdownCacheLimit {
            markdownCache.removeAll(keepingCapacity: true)
        }
        markdownCache[text] = result
        return result
    }

    /// 行内解析；失败或解析出空内容（链接定义、未闭合标签等）时回退纯文本。
    private static func renderInlineOnly(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ), !attributed.characters.isEmpty {
            return attributed
        }
        return AttributedString(text)
    }

    /// Apple 的行内解析会把 ``` 当作行内代码定界、折叠围栏代码块并泄漏语言名。
    /// 按围栏拆分，代码体按纯文本逐行保留，其余按行内 markdown。
    private static func renderWithFencedCodeBlocks(_ text: String) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var inFence = false
        var hasOutput = false

        func flush() {
            guard !buffer.isEmpty else { return }
            let piece = inFence ? AttributedString(buffer) : renderInlineOnly(buffer)
            if hasOutput { result.append(AttributedString("\n")) }
            result.append(piece)
            hasOutput = true
            buffer = ""
        }

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush()
                inFence.toggle()
                continue
            }
            if !buffer.isEmpty { buffer.append("\n") }
            buffer.append(line)
        }
        flush()
        return result
    }

    /// 去掉 `::directive{...}`（可能跨行）指令块。
    private static func stripDirectives(_ text: String) -> String {
        var result: [String] = []
        var inDirective = false
        var braceDepth = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if inDirective {
                for ch in line {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth <= 0 {
                    inDirective = false
                    braceDepth = 0
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("::") && trimmed.contains("{") {
                braceDepth = 0
                for ch in line {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                }
                if braceDepth > 0 { inDirective = true }
                continue
            }
            result.append(String(line))
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 逐行 trim 并合并连续空行。
    private static func compactText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { acc, line in
                if line.isEmpty && (acc.last?.isEmpty ?? true) { return }
                acc.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
