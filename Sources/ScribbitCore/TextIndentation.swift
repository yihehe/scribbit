import Foundation

/// A single replacement keeps native undo atomic. All offsets are UTF-16,
/// matching NSTextView/NSString rather than Swift Character indices.
public struct IndentationEdit: Equatable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

public enum TextIndentation {
    public static let spacesPerLevel = 4

    /// Remove one leading tab or up to four leading ASCII spaces from each
    /// touched line. An end selection at column zero does not touch that line.
    /// A caret on the empty line after a trailing newline is a no-op.
    public static func outdent(_ text: String, selection: NSRange) -> IndentationEdit? {
        let source = text as NSString
        guard selection.location >= 0, selection.location <= source.length,
              selection.length >= 0, selection.length <= source.length - selection.location else { return nil }
        let first = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let lastPosition = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        let last = source.lineRange(for: NSRange(location: lastPosition, length: 0))
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var removals: [NSRange] = []
        var start = block.location
        while start < NSMaxRange(block) {
            let line = source.lineRange(for: NSRange(location: start, length: 0))
            var count = 0
            if source.character(at: start) == 9 {
                count = 1
            } else {
                while count < spacesPerLevel, start + count < NSMaxRange(line),
                      source.character(at: start + count) == 32 { count += 1 }
            }
            if count > 0 { removals.append(NSRange(location: start, length: count)) }
            guard NSMaxRange(line) > start else { break }
            start = NSMaxRange(line)
        }
        guard !removals.isEmpty else { return nil }
        let replacement = NSMutableString(string: source.substring(with: block))
        for removal in removals.reversed() {
            replacement.deleteCharacters(in: NSRange(location: removal.location - block.location, length: removal.length))
        }
        func mapped(_ position: Int) -> Int {
            position - removals.reduce(0) { total, removal in
                total + min(removal.length, max(0, position - removal.location))
            }
        }
        let begin = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        return IndentationEdit(range: block, replacement: replacement as String,
                               selection: NSRange(location: begin, length: end - begin))
    }
}
