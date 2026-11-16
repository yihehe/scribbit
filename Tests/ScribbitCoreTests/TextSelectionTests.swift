import Foundation
import Testing
@testable import ScribbitCore

struct TextSelectionTests {
    @Test func preservesValidCaretAndSelection() {
        for range in [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0),
                      NSRange(location: 1, length: 3), NSRange(location: 5, length: 0)] {
            #expect(TextSelection.clamped(range, in: "hello") == range)
        }
    }
    @Test func boundsAndOverflow() {
        #expect(TextSelection.clamped(NSRange(location: 99, length: 99), in: "") == NSRange(location: 0, length: 0))
        #expect(TextSelection.clamped(NSRange(location: 99, length: 0), in: "hi") == NSRange(location: 2, length: 0))
        #expect(TextSelection.clamped(NSRange(location: 1, length: Int.max), in: "hi") == NSRange(location: 1, length: 1))
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: -1, length: 0),
                      NSRange(location: 0, length: -1)] {
            #expect(TextSelection.clamped(range, in: "hi") == NSRange(location: 0, length: 0))
        }
    }
    @Test func caretNeverSplitsComposedCharacters() {
        for source in ["a😀b", "ae\u{301}b", "a👩🏽‍💻b"] {
            let character = (source as NSString).rangeOfComposedCharacterSequence(at: 1)
            for offset in character.location..<NSMaxRange(character) {
                #expect(TextSelection.clamped(NSRange(location: offset, length: 0), in: source)
                        == NSRange(location: 1, length: 0))
            }
            #expect(TextSelection.clamped(NSRange(location: 2, length: 1), in: source) == character)
        }
    }
    @Test func preservesLineSeparatorOffsets() {
        let source = "a\r\nb\u{2028}c"
        let line = NSRange(location: 3, length: 2)
        #expect(TextSelection.clamped(line, in: source) == line)
        #expect(TextSelection.clamped(NSRange(location: 3, length: 0), in: source)
                == NSRange(location: 3, length: 0))
    }
    @Test func shortenedUnicodeSourceClipsToLegalEnd() {
        #expect(TextSelection.clamped(NSRange(location: 100, length: 20), in: "🐸")
                == NSRange(location: 2, length: 0))
        #expect(TextSelection.clamped(NSRange(location: 1, length: 99), in: "🐸")
                == NSRange(location: 0, length: 2))
    }
}
