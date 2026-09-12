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
