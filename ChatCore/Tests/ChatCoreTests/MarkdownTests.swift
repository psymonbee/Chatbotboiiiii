import Testing
@testable import ChatCore

@Suite struct MarkdownTests {
    @Test func mixedDocument() {
        let source = """
        # Basics
        Balance is **key**.
        Eat well.

        - one
          - nested
        2. two

        > quoted
        > more

        ```swift
        let x = 1
        ```
        ---
        | Food | Protein |
        |------|:-------:|
        | Egg  | 6g |
        """
        let blocks = Markdown.blocks(from: source)
        #expect(blocks == [
            .heading(level: 1, text: "Basics"),
            .paragraph("Balance is **key**.\nEat well."),
            .listItem(marker: "•", indent: 0, text: "one"),
            .listItem(marker: "•", indent: 1, text: "nested"),
            .listItem(marker: "2.", indent: 0, text: "two"),
            .quote("quoted\nmore"),
            .code(language: "swift", code: "let x = 1"),
            .rule,
            .table(header: ["Food", "Protein"], rows: [["Egg", "6g"]]),
        ])
    }

    @Test func unclosedFenceWhileStreaming() {
        let blocks = Markdown.blocks(from: "Here:\n```\nprint(1)\nprint(2")
        #expect(blocks == [.paragraph("Here:"), .code(language: nil, code: "print(1)\nprint(2")])
    }

    @Test func hashWithoutSpaceIsNotHeading() {
        #expect(Markdown.blocks(from: "#hashtag") == [.paragraph("#hashtag")])
    }

    @Test func taskListsAndSpeech() {
        #expect(Markdown.blocks(from: "- [x] done") == [.listItem(marker: "☑", indent: 0, text: "done")])
        let spoken = Markdown.speakableText(from: "## Hi\nSee **[docs](https://x.y)**\n```\ncode\n```")
        #expect(spoken == "Hi\nSee docs")
    }
}
