import Testing
@testable import Folio

@Suite("Markdown parser")
struct MarkdownParserTests {

    /// A fence indented under a list item indents its content too. That indent is
    /// the list's, not the code's — rendered, it showed as two stray spaces on
    /// every source line, and the wrapped tail of a long line then sat *left* of
    /// the line it belonged to.
    @Test("An indented fence loses the list indent but keeps the code's own")
    func indentedFenceStripsListIndent() {
        let md = """
        1. Step

           ```sh
           ./cutover.ts write phone_number
             --apply
           ```
        """
        let code = MarkdownParser.parse(md).compactMap { block -> String? in
            if case let .code(_, text) = block.kind { return text }
            return nil
        }
        #expect(code == ["./cutover.ts write phone_number\n  --apply"])
    }

    @Test("A line indented less than the fence is not cut into")
    func shallowLineSurvives() {
        let md = "   ```\n  x\n   ```"
        let code = MarkdownParser.parse(md).compactMap { block -> String? in
            if case let .code(_, text) = block.kind { return text }
            return nil
        }
        #expect(code == ["x"])
    }
}

extension MarkdownParserTests {
    private func codeBlocks(_ md: String) -> [String] {
        MarkdownParser.parse(md).compactMap { block -> String? in
            if case let .code(_, text) = block.kind { return text }
            return nil
        }
    }

    /// TextKit treats a stray CR as a paragraph break, so a CRLF file's code
    /// block — joined with soft breaks — would fall apart into one card per line.
    @Test("CRLF line endings do not leak into a code block")
    func crlfStripped() {
        #expect(codeBlocks("```\r\na\r\nb\r\n```\r\n") == ["a\nb"])
    }

    @Test("Dedent counts tabs by column")
    func tabDedent() {
        // Two-space fence: a tab-indented line keeps the two columns it had beyond the fence.
        #expect(codeBlocks("  ```\n  a\n\tb\n  ```") == ["a\n  b"])
        // Tab-indented fence under a list item whose content indent is the same
        // four columns (a bare top-level tab would be indented code, not a fence).
        // A four-space line is fully dedented, a tab is consumed whole, and the
        // code's own deeper indent survives.
        #expect(codeBlocks("-   item\n\n\t```\n    a\n\tb\n\t\tc\n\t```") == ["a\nb\n\tc"])
    }
}
