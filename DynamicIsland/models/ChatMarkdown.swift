import Foundation

/// A deliberately bounded Markdown subset for chat. Unknown syntax remains visible text.
/// Foundation only: the parser and inline safety policy can be tested without SwiftUI.
enum ChatMarkdown {
    indirect enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case list([ListItem])
        case quote([Block])
        case code(language: String?, content: String, isClosed: Bool)
        case table(Table)
        case rule
    }

    struct ListItem: Equatable {
        /// Keep the author's numbers, including lists that start at a number other than one.
        let marker: String
        let blocks: [Block]
    }

    struct Table: Equatable {
        enum Alignment: Equatable { case leading, center, trailing }
        let headers: [String]
        let alignments: [Alignment]
        let rows: [[String]]
    }

    static func parse(_ source: String) -> [Block] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return parseLines(normalized.components(separatedBy: "\n"), depth: 0)
    }

    /// Text never loads images. Preserve image/HTML/reference syntax literally rather
    /// than allowing Foundation's inline parser to silently discard unsupported content.
    static func inline(_ source: String) -> AttributedString {
        if source.range(of: #"!\[|<[^>]+>|^\s*\[[^\]]+\]:"#, options: .regularExpression) != nil {
            return AttributedString(source)
        }
        var result = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                           failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(source)
        // Disallow file:, javascript:, custom app schemes and relative destinations.
        let unsafeRanges = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let url = run.link else { return nil }
            return isSafeLink(url) ? nil : run.range
        }
        for range in unsafeRanges { result[range].link = nil }
        return result
    }

    static func isSafeLink(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "http": return url.host?.isEmpty == false
        // URL.path is empty for opaque mailto URLs on macOS; URLComponents
        // correctly exposes the address as the path component.
        case "mailto": return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.isEmpty == false
        default: return false
        }
    }

    private struct Marker {
        let indent: Int
        let contentIndent: Int
        let label: String
        let ordered: Bool
        let text: String
    }

    private static func indentation(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { count, character in
            character == "\t" ? count + (4 - count % 4) : count + 1
        }
    }

    private static func droppingIndent(_ line: String, _ count: Int) -> String {
        var removed = 0
        var index = line.startIndex
        while index < line.endIndex, removed < count {
            let character = line[index]
            guard character == " " || character == "\t" else { break }
            removed += character == "\t" ? 4 - removed % 4 : 1
            index = line.index(after: index)
        }
        return String(repeating: " ", count: max(0, removed - count)) + line[index...]
    }

    private static func marker(_ line: String) -> Marker? {
        let indent = indentation(line)
        let text = droppingIndent(line, indent)
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        var end = 0
        let ordered: Bool
        if "-*+".contains(characters[0]) {
            end = 1
            ordered = false
        } else {
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            guard end > 0, end <= 9, end < characters.count,
                  characters[end] == "." || characters[end] == ")" else { return nil }
            end += 1
            ordered = true
        }
        guard end == characters.count || characters[end].isWhitespace else { return nil }
        let label = ordered ? String(characters[..<end]) : "•"
        var contentStart = end
        while contentStart < characters.count, characters[contentStart].isWhitespace { contentStart += 1 }
        return Marker(indent: indent, contentIndent: indent + max(end + 1, contentStart),
                      label: label, ordered: ordered, text: String(characters[contentStart...]))
    }

    private static func fence(_ line: String) -> (character: Character, count: Int, info: String)? {
        guard indentation(line) <= 3 else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first == "`" || first == "~" else { return nil }
        let count = text.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        let info = String(text.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        guard first != "`" || !info.contains("`") else { return nil }
        return (first, count, info)
    }

    private static func heading(_ line: String) -> (Int, String)? {
        guard indentation(line) <= 3 else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        let level = text.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = text.dropFirst(level)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        let title = String(rest).trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        return (level, title)
    }

    private static func setextLevel(_ line: String) -> Int? {
        guard indentation(line) <= 3 else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.first, first == "=" || first == "-",
              text.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    private static func isRule(_ line: String) -> Bool {
        guard indentation(line) <= 3 else { return false }
        let text = line.filter { !$0.isWhitespace }
        guard text.count >= 3, let first = text.first, "*-_".contains(first) else { return false }
        return text.allSatisfy { $0 == first }
    }

    private static func quoteText(_ line: String) -> String? {
        guard indentation(line) <= 3 else { return nil }
        let text = droppingIndent(line, indentation(line))
        guard text.first == ">" else { return nil }
        let rest = text.dropFirst()
        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    /// Split only unescaped pipes outside paired code spans. Backslashes are kept
    /// for the inline parser; unmatched backticks must not swallow streaming cells.
    private static func cells(_ line: String) -> [String]? {
        let chars = Array(line.trimmingCharacters(in: .whitespaces))
        var result: [String] = []
        var cell = ""
        var index = 0
        var separators: [Int] = []
        while index < chars.count {
            if chars[index] == "\\", index + 1 < chars.count {
                cell.append(chars[index]); cell.append(chars[index + 1]); index += 2
            } else if chars[index] == "`" {
                var end = index
                while end < chars.count, chars[end] == "`" { end += 1 }
                let count = end - index
                var closing = end
                var matchedEnd: Int?
                while closing < chars.count {
                    if chars[closing] == "`" {
                        var runEnd = closing
                        while runEnd < chars.count, chars[runEnd] == "`" { runEnd += 1 }
                        if runEnd - closing == count { matchedEnd = runEnd; break }
                        closing = runEnd
                    } else { closing += 1 }
                }
                let spanEnd = matchedEnd ?? end
                cell += String(chars[index..<spanEnd]); index = spanEnd
            } else if chars[index] == "|" {
                separators.append(index)
                result.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""; index += 1
            } else {
                cell.append(chars[index]); index += 1
            }
        }
        guard !separators.isEmpty else { return nil }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        if separators.last == chars.count - 1 { result.removeLast() }
        if separators.first == 0 { result.removeFirst() }
        return result.isEmpty ? nil : result
    }

    private static func tableHeader(_ lines: [String], _ index: Int) -> Table? {
        guard index + 1 < lines.count, let headers = cells(lines[index]),
              let separators = cells(lines[index + 1]), headers.count == separators.count else { return nil }
        var alignments: [Table.Alignment] = []
        for separator in separators {
            guard separator.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else { return nil }
            alignments.append(separator.hasSuffix(":") ? (separator.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return Table(headers: headers, alignments: alignments, rows: [])
    }

    private static func startsBlock(_ lines: [String], _ index: Int) -> Bool {
        let line = lines[index]
        return line.trimmingCharacters(in: .whitespaces).isEmpty || fence(line) != nil
            || heading(line) != nil || marker(line) != nil || quoteText(line) != nil
            || isRule(line) || tableHeader(lines, index) != nil
    }

    private static func parseLines(_ lines: [String], depth: Int) -> [Block] {
        // Bound recursion for model-generated or pasted adversarial nesting.
        guard depth < 32 else { return [.paragraph(lines.joined(separator: "\n"))] }
        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if let opening = fence(line) {
                index += 1
                var content = ""
                var closed = false
                while index < lines.count {
                    if let closing = fence(lines[index]), closing.character == opening.character,
                       closing.count >= opening.count, closing.info.isEmpty {
                        closed = true; index += 1; break
                    }
                    content += droppingIndent(lines[index], indentation(line))
                    if index + 1 < lines.count { content += "\n" }
                    index += 1
                }
                blocks.append(.code(language: opening.info.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
                                    content: content, isClosed: closed))
            } else if let (level, title) = heading(line) {
                blocks.append(.heading(level: level, text: title)); index += 1
            } else if isRule(line) {
                blocks.append(.rule); index += 1
            } else if quoteText(line) != nil {
                var quoted: [String] = []
                while index < lines.count, let text = quoteText(lines[index]) {
                    quoted.append(text); index += 1
                }
                blocks.append(.quote(parseLines(quoted, depth: depth + 1)))
            } else if let first = marker(line) {
                var items: [ListItem] = []
                while index < lines.count, let current = marker(lines[index]),
                      current.indent == first.indent, current.ordered == first.ordered,
                      !isRule(lines[index]) {
                    var itemLines = [current.text]
                    index += 1
                    while index < lines.count {
                        if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                            var next = index + 1
                            while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                            guard next < lines.count, indentation(lines[next]) >= current.contentIndent else { break }
                            itemLines.append(""); index += 1
                        } else if indentation(lines[index]) >= current.contentIndent {
                            itemLines.append(droppingIndent(lines[index], current.contentIndent)); index += 1
                        } else if marker(lines[index]) == nil, !startsBlock(lines, index),
                                  setextLevel(lines[index]) == nil {
                            itemLines.append(lines[index]); index += 1
                        } else { break }
                    }
                    items.append(ListItem(marker: current.label, blocks: parseLines(itemLines, depth: depth + 1)))
                    // Blank lines between sibling items belong to the same list.
                    var next = index
                    while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                    if next < lines.count, let sibling = marker(lines[next]),
                       sibling.indent == first.indent, sibling.ordered == first.ordered { index = next }
                }
                blocks.append(.list(items))
            } else if let header = tableHeader(lines, index) {
                index += 2
                var rows: [[String]] = []
                while index < lines.count, !startsNonTableBlock(lines[index]), let row = cells(lines[index]) {
                    // Extra cells are not discarded: malformed rows fall back to visible text.
                    guard row.count <= header.headers.count else { break }
                    rows.append(row + Array(repeating: "", count: header.headers.count - row.count)); index += 1
                }
                blocks.append(.table(Table(headers: header.headers, alignments: header.alignments, rows: rows)))
            } else {
                var paragraph = [line]
                index += 1
                var level: Int?
                while index < lines.count {
                    if let underline = setextLevel(lines[index]) { level = underline; index += 1; break }
                    if startsBlock(lines, index) { break }
                    paragraph.append(lines[index]); index += 1
                }
                let text = paragraph.joined(separator: "\n")
                blocks.append(level.map { .heading(level: $0, text: text) } ?? .paragraph(text))
            }
        }
        return blocks
    }

    private static func startsNonTableBlock(_ line: String) -> Bool {
        fence(line) != nil || heading(line) != nil || quoteText(line) != nil || marker(line) != nil || isRule(line)
    }
}
