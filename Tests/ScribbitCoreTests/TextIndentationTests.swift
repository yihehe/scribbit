import Foundation
import Testing
@testable import ScribbitCore

struct TextIndentationTests {
    private func apply(_ edit: IndentationEdit, to source: String) -> String {
        (source as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
    @Test func testCaretOutdentsLeadingTabAndPreservesCaretColumn() throws {
        let edit = try #require(TextIndentation.outdent("\titem", selection: NSRange(location: 5, length: 0)))
        #expect(apply(edit, to: "\titem") == "item")
        #expect(edit.selection == NSRange(location: 4, length: 0))
    }
    @Test(arguments: [1, 2, 3, 4, 5, 8]) func testRemovesAtMostFourLeadingSpaces(count: Int) throws {
        let source = String(repeating: " ", count: count) + "item"
        let edit = try #require(TextIndentation.outdent(source, selection: NSRange(location: count + 4, length: 0)))
        #expect(apply(edit, to: source) == String(repeating: " ", count: max(0, count - 4)) + "item")
        #expect(edit.selection.location == source.utf16.count - min(count, 4))
    }
    @Test func testCaretWithinRemovedIndentCollapsesToStart() throws {
        let edit = try #require(TextIndentation.outdent("    item", selection: NSRange(location: 2, length: 0)))
        #expect(edit.selection == NSRange(location: 0, length: 0))
    }
    @Test func testMixedIndentRemovesOnlyOnePrefixLevel() throws {
        let source = "\t  a\n  \tb"
        let edit = try #require(TextIndentation.outdent(source, selection: NSRange(location: 0, length: source.utf16.count)))
        #expect(apply(edit, to: source) == "  a\n\tb")
    }
    @Test func testSelectedLinesOutdentWithoutChangingInternalWhitespace() throws {
        let source = "before\n\tfoo\tbar\n    baz\nafter"
        let selection = (source as NSString).range(of: "foo\tbar\n    baz")
        let edit = try #require(TextIndentation.outdent(source, selection: selection))
        #expect(apply(edit, to: source) == "before\nfoo\tbar\nbaz\nafter")
        #expect(edit.selection == (apply(edit, to: source) as NSString).range(of: "foo\tbar\nbaz"))
    }
    @Test func testSelectionEndingAtNextLineStartDoesNotOutdentIt() throws {
        let source = "\ta\n\tb\n\tc"
        let edit = try #require(TextIndentation.outdent(source, selection: NSRange(location: 0, length: 3)))
        #expect(apply(edit, to: source) == "a\n\tb\n\tc")
        #expect(edit.selection == NSRange(location: 0, length: 2))
    }
    @Test func testUnicodeSelectionAndCombiningBytesSurvive() throws {
        let source = "\t😀foo\n    cafe\u{301}\nz"
        let selection = (source as NSString).range(of: "😀foo\n    cafe\u{301}")
        let edit = try #require(TextIndentation.outdent(source, selection: selection))
        let expected = "😀foo\ncafe\u{301}\nz"
        #expect(Data(apply(edit, to: source).utf8) == Data(expected.utf8))
        #expect(edit.selection == (expected as NSString).range(of: "😀foo\ncafe\u{301}"))
    }
    @Test(arguments: ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"])
    func testPreservesOriginalLineSeparators(separator: String) throws {
        let source = "\tfirst" + separator + "    second" + separator + "last"
        let edit = try #require(TextIndentation.outdent(source, selection: NSRange(location: 0, length: source.utf16.count)))
        #expect(apply(edit, to: source) == "first" + separator + "second" + separator + "last")
    }
    @Test func testNoIndentEmptyTextAndInternalTabsAreNoOps() {
        for source in ["", "item", "a\tb", "\u{00a0}item"] {
            #expect(TextIndentation.outdent(source, selection: NSRange(location: 0, length: source.utf16.count)) == nil)
        }
    }
    @Test func testCaretAfterTrailingNewlineDoesNotModifyPreviousLine() {
        #expect(TextIndentation.outdent("\titem\n", selection: NSRange(location: 6, length: 0)) == nil)
    }
    @Test func testCaretAtEOFWithoutNewlineOutdentsLastLine() throws {
        let edit = try #require(TextIndentation.outdent("\titem", selection: NSRange(location: 5, length: 0)))
        #expect(apply(edit, to: "\titem") == "item")
    }
    @Test func testWhitespaceOnlyLinesAndSelectionInsideIndent() throws {
        let source = "    \n\tx"
        let edit = try #require(TextIndentation.outdent(source, selection: NSRange(location: 2, length: 4)))
        #expect(apply(edit, to: source) == "\nx")
        #expect(edit.selection == NSRange(location: 0, length: 1))
    }
    @Test func testMalformedRangesFailWithoutOverflow() {
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: Int.max),
                      NSRange(location: 99, length: 0), NSRange(location: -1, length: 0), NSRange(location: 0, length: -1)] {
            #expect(TextIndentation.outdent("\titem", selection: range) == nil)
        }
    }
}
