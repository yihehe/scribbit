import AppKit
import ScribbitCore

/// AppKit owns editing, composition, clipboard, selection, find and undo.
/// The only extra editing command is leading-whitespace outdent.
final class NoteTextView: NSTextView {
    override func insertBacktab(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1,
              let storage = textStorage,
              let edit = TextIndentation.outdent(string, selection: selectedRange()) else { return }
        breakUndoCoalescing()
        let manager = undoManager
        manager?.beginUndoGrouping()
        defer { manager?.endUndoGrouping() }
        guard shouldChangeText(inRanges: [NSValue(range: edit.range)],
                               replacementStrings: [edit.replacement]) else { return }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        setSelectedRange(edit.selection)
        didChangeText()
        breakUndoCoalescing()
        manager?.setActionName("Unindent")
    }
}
