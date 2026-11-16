import Foundation

/// AppKit selections use UTF-16 offsets. A refreshed file may be shorter or have
/// different Unicode at the saved offset; never restore half a character.
public enum TextSelection {
    public static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let source = text as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else {
            return NSRange(location: 0, length: 0)
        }
        let start = min(range.location, source.length)
        let length = min(range.length, source.length - start)
        if length > 0 {
            return source.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: length))
        }
        let caret = start < source.length
            ? source.rangeOfComposedCharacterSequence(at: start).location : start
        return NSRange(location: caret, length: 0)
    }
}
