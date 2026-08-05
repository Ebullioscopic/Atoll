import XCTest
@testable import CodeIslandCore

final class ChatMessageTextFormatterTests: XCTestCase {
    func testUserMessagesStayLiteralEvenWhenTheyContainMarkdownSyntax() {
        let rendered = ChatMessageTextFormatter.displayText(
            for: ChatMessage(isUser: true, text: "~/demo/path ~~draft~~ `--flag`")
        )

        XCTAssertEqual(String(rendered.characters), "~/demo/path ~~draft~~ `--flag`")
        XCTAssertTrue(rendered.runs.allSatisfy { $0.inlinePresentationIntent == nil })
    }

    func testAssistantMessagesStillRenderInlineMarkdown() {
        let rendered = ChatMessageTextFormatter.displayText(
            for: ChatMessage(isUser: false, text: "**Done**")
        )

        XCTAssertEqual(String(rendered.characters), "Done")
        XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent != nil })
    }

    // MARK: - Fenced code blocks (issue #101)

    func testFencedCodeBlockDoesNotLeakLanguageIdentifierOrCollapseNewlines() {
        let rendered = ChatMessageTextFormatter.inlineMarkdown(
            "```fish\nfish_add_path -U ~/.local/bin\n```"
        )
        let text = String(rendered.characters)

        XCTAssertFalse(text.contains("fish_add_path -U ~/.local/bin fish"),
                       "Language identifier leaked into inline code run")
        XCTAssertFalse(text.hasPrefix("fish "),
                       "Language identifier was emitted as text before the code body")
        XCTAssertTrue(text.contains("fish_add_path -U ~/.local/bin"),
                      "Code content is missing from the rendered output")
        XCTAssertFalse(text.contains("```"), "Fence markers should be stripped")
    }

    func testFencedCodeBlockWithoutLanguagePreservesContent() {
        let rendered = ChatMessageTextFormatter.inlineMarkdown(
            "```\nline one\nline two\n```"
        )
        let text = String(rendered.characters)

        XCTAssertTrue(text.contains("line one"))
        XCTAssertTrue(text.contains("line two"))
        XCTAssertTrue(text.contains("\n"), "Newlines between code lines must be preserved")
        XCTAssertFalse(text.contains("```"))
    }

    func testMixedProseAndFencedCodeKeepsBothIntact() {
        let rendered = ChatMessageTextFormatter.inlineMarkdown(
            "Run the following:\n```sh\necho hi\n```\nand you're done."
        )
        let text = String(rendered.characters)

        XCTAssertTrue(text.contains("Run the following:"))
        XCTAssertTrue(text.contains("echo hi"))
        XCTAssertTrue(text.contains("and you're done."))
        XCTAssertFalse(text.contains("```"))
        XCTAssertFalse(text.contains("sh echo hi"),
                       "Language identifier must not merge into the code content")
    }

    func testMarkdownSpecialCharsInsideFenceAreNotInterpreted() {
        let rendered = ChatMessageTextFormatter.inlineMarkdown(
            "```\nvar x = *y* + `z`\n```"
        )
        let text = String(rendered.characters)

        XCTAssertTrue(text.contains("*y*"), "Emphasis markers inside code must stay literal")
        XCTAssertTrue(text.contains("`z`"), "Inline code markers inside fence must stay literal")
    }
}
