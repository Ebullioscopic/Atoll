import Foundation

// Run from Atoll:
// swiftc DynamicIsland/models/ChatMarkdown.swift tests/markdown/main.swift -o /tmp/atoll-markdown-tests
// /tmp/atoll-markdown-tests
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    guard condition() else { fatalError("Line \(line): \(message)") }
}
func plain(_ source: String) -> String { String(ChatMarkdown.inline(source).characters) }

expect(ChatMarkdown.parse("").isEmpty, "Empty streaming response")
expect(ChatMarkdown.parse(" \n\t\n").isEmpty, "Whitespace response")
expect(ChatMarkdown.parse("# Title\nfirst line\nsecond line\n\n## Next ##\nbody") == [
    .heading(level: 1, text: "Title"), .paragraph("first line\nsecond line"),
    .heading(level: 2, text: "Next"), .paragraph("body")
], "ATX headings and multiline paragraphs stay separate")
expect(ChatMarkdown.parse("First line\nsecond line\n===\n\nSmall\n---") == [
    .heading(level: 1, text: "First line\nsecond line"), .heading(level: 2, text: "Small")
], "Multiline setext headings")
expect(ChatMarkdown.parse("#hashtag\n####### unsupported") == [.paragraph("#hashtag\n####### unsupported")],
       "Unsupported heading syntax remains visible")
expect(ChatMarkdown.parse("Hello\r\nworld\r\n\r\nNext") == [.paragraph("Hello\nworld"), .paragraph("Next")],
       "CRLF normalization")
expect(ChatMarkdown.parse("---\n***\n___") == [.rule, .rule, .rule], "Thematic breaks")

let nestedList: ChatMarkdown.Block = .list([
    .init(marker: "8)", blocks: [.paragraph("nested")])
])
let childList: ChatMarkdown.Block = .list([
    .init(marker: "•", blocks: [.paragraph("child"), nestedList])
])
expect(ChatMarkdown.parse("3. Three\n4. Four\n   continuation\n   - child\n     8) nested\n5. Five") == [
    .list([
        .init(marker: "3.", blocks: [.paragraph("Three")]),
        .init(marker: "4.", blocks: [.paragraph("Four\ncontinuation"), childList]),
        .init(marker: "5.", blocks: [.paragraph("Five")])])
], "Ordered and nested mixed lists retain markers and continuation lines")
expect(ChatMarkdown.parse("- first\n\n- second\n\n  second paragraph\n\nOutside") == [
    .list([.init(marker: "•", blocks: [.paragraph("first")]),
           .init(marker: "•", blocks: [.paragraph("second"), .paragraph("second paragraph")])]),
    .paragraph("Outside")
], "Loose list and indented paragraphs do not swallow outside text")
expect(ChatMarkdown.parse("- one\nlazy continuation\n+ two\n1. ordered") == [
    .list([.init(marker: "•", blocks: [.paragraph("one\nlazy continuation")]),
           .init(marker: "•", blocks: [.paragraph("two")])]),
    .list([.init(marker: "1.", blocks: [.paragraph("ordered")])])
], "Lazy list continuation and changed list kinds")
expect(ChatMarkdown.parse("> ## Quote\n> text\n>\n> - item\n>> nested") == [
    .quote([.heading(level: 2, text: "Quote"), .paragraph("text"),
            .list([.init(marker: "•", blocks: [.paragraph("item")])]), .quote([.paragraph("nested")])])
], "Quotes recursively render headings, lists and nested quotes")

expect(ChatMarkdown.parse("```swift\nlet x = 1\n\nprint(x)\n```\nAfter") == [
    .code(language: "swift", content: "let x = 1\n\nprint(x)", isClosed: true), .paragraph("After")
], "Closed code keeps internal whitespace without adding a line for the closing fence")
expect(ChatMarkdown.parse("```\n```") == [.code(language: nil, content: "", isClosed: true)], "Empty closed fence")
expect(ChatMarkdown.parse("```swift") == [.code(language: "swift", content: "", isClosed: false)], "Opening fence only")
expect(ChatMarkdown.parse("```swift\nlet x =") == [.code(language: "swift", content: "let x =", isClosed: false)],
       "Streaming content without final newline")
expect(ChatMarkdown.parse("```\nhello\n``") == [.code(language: nil, content: "hello\n``", isClosed: false)],
       "Incomplete closing fence remains visible")
expect(ChatMarkdown.parse("````text\n```\n~~~\n````") == [.code(language: "text", content: "```\n~~~", isClosed: true)],
       "Fence closing must match character and minimum length")
expect(ChatMarkdown.parse("~~~python extra\nx\n~~~~") == [.code(language: "python", content: "x", isClosed: true)],
       "Tilde fences and info strings")
expect(ChatMarkdown.parse("- code\n  ```swift\n  x\n  ```") == [
    .list([.init(marker: "•", blocks: [.paragraph("code"), .code(language: "swift", content: "x", isClosed: true)])])
], "Fenced code nested in a list")

for (source, content) in [
    ("```\nline\n```", "line"),
    ("```\nline\n```\n\n", "line"),
    ("```\nline\n\n```", "line\n"),
    ("```\nline\n\n\n```", "line\n\n"),
    ("```\n\nline\n```", "\nline"),
    ("```\n\n\n```", "\n"),
    ("```\nline  \n \n```", "line  \n "),
    ("~~~\r\nline\r\n\r\n~~~", "line\n")
] {
    expect(ChatMarkdown.parse(source) == [.code(language: nil, content: content, isClosed: true)],
           "Closed fence strips only the fence separator, preserving actual blank lines: \(String(reflecting: source))")
}
let streamingCode = "let x = 1\n\n  print(x)\n"
for length in 0...streamingCode.count {
    let partial = String(streamingCode.prefix(length))
    expect(ChatMarkdown.parse("```swift\n" + partial) == [.code(language: "swift", content: partial, isClosed: false)],
           "Streaming prefix \(length) preserves every received code character, including final newlines")
}
expect(ChatMarkdown.parse("> ```\n> line\n>\n> ```") == [
    .quote([.code(language: nil, content: "line\n", isClosed: true)])
], "Quoted code preserves its explicit trailing blank line")

let tableSource = "| Name | Value | Note |\n| :--- | ---: | :---: |\n| A\\|B | **2** | `a|b` |\n| short | 3 |"
expect(ChatMarkdown.parse(tableSource) == [.table(.init(
    headers: ["Name", "Value", "Note"], alignments: [.leading, .trailing, .center],
    rows: [["A\\|B", "**2**", "`a|b`"], ["short", "3", ""]]))],
       "Tables respect escaped pipes, inline code pipes, alignment and missing cells")
expect(ChatMarkdown.parse("A | B\n--- | ---\nx | y") == [.table(.init(
    headers: ["A", "B"], alignments: [.leading, .leading], rows: [["x", "y"]]))], "Optional outer pipes")
expect(ChatMarkdown.parse("| A |\n| --- |\n| value |") == [.table(.init(
    headers: ["A"], alignments: [.leading], rows: [["value"]]))], "Single-column table")
expect(ChatMarkdown.parse("A | B\n-- | ---\nx | y") == [.paragraph("A | B\n-- | ---\nx | y")],
       "Incomplete table delimiter remains text")
expect(ChatMarkdown.parse("A | B\n--- | ---\nx | y | z") == [
    .table(.init(headers: ["A", "B"], alignments: [.leading, .leading], rows: [])), .paragraph("x | y | z")
], "Extra table cells fall back visibly instead of losing data")
expect(ChatMarkdown.parse("A | B\n--- | ---\n`partial | value") == [.table(.init(
    headers: ["A", "B"], alignments: [.leading, .leading], rows: [["`partial", "value"]]))],
       "Unmatched inline backtick does not swallow table columns")
expect(ChatMarkdown.parse("A | B\n--- | ---\n``a`|b`` | c") == [.table(.init(
    headers: ["A", "B"], alignments: [.leading, .leading], rows: [["``a`|b``", "c"]]))],
       "Variable length code span delimiters in table cells")

expect(plain("plain 中文 text\nnext line  ") == "plain 中文 text\nnext line  ", "Plain text and whitespace preserved")
expect(plain("**bold** *italic* ~~gone~~ `x < y`") == "bold italic gone x < y", "Inline formatting content")
let formatted = ChatMarkdown.inline("**bold** *italic* ~~gone~~ `code`")
expect(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "Bold attribute")
expect(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true }, "Italic attribute")
expect(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.strikethrough) == true }, "Strikethrough attribute")
expect(formatted.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true }, "Inline code attribute")
expect(plain(#"escaped \*literal\* and A\|B"#) == "escaped *literal* and A|B", "Inline escapes")
let linked = ChatMarkdown.inline("[site](https://example.com) and [mail](mailto:test@example.com)")
expect(linked.runs.filter { $0.link != nil }.count == 2, "Web and email links remain interactive")
for destination in ["file:///etc/passwd", "javascript:alert", "atoll://command", "relative/path", "data:text/plain,test"] {
    let value = ChatMarkdown.inline("[label](\(destination))")
    expect(String(value.characters) == "label", "Unsafe link still has readable text")
    expect(value.runs.allSatisfy { $0.link == nil }, "Unsafe link is not actionable: \(destination)")
}
for source in ["![remote](https://example.com/a.png)", "<div>visible</div>", "[ref]: https://example.com", "$$x^2$$", "- [ ] task"] {
    expect(plain(source) == source, "Unsupported inline syntax stays visible: \(source)")
}
expect(ChatMarkdown.parse("    indented code\n    stays visible") == [.paragraph("    indented code\n    stays visible")],
       "Unsupported indented code remains visible")

// Every prefix of a realistic streamed response must parse without a crash or a hang.
let streamed = "# Result\n\n- **first**\n  - child\n\n" + tableSource + "\n\n```swift\nprint(\"hello\")\n```"
for end in streamed.indices { _ = ChatMarkdown.parse(String(streamed[..<end])) }
expect(ChatMarkdown.parse(String(repeating: "> ", count: 200) + "deep").count == 1, "Bounded quote nesting")
expect(ChatMarkdown.parse("```\n" + String(repeating: "x", count: 20_000)).count == 1, "Long code line")
print("Markdown tests passed: \(checks) checks plus \(streamed.count) streaming prefixes")
