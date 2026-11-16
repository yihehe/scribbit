import AppKit

/// A GUI-harness driver only. Production editing uses AppKit's native APIs.
@MainActor
struct EditorProbe {
    let view: NSTextView
    static func find(in root: NSView) -> EditorProbe? {
        // Selectable file paths/error labels are not the source editor.
        if let native = root as? NoteTextView { return EditorProbe(view: native) }
        return root.subviews.compactMap { find(in: $0) }.first
    }
    var string: String { view.string }
    var window: NSWindow? { view.window }
    var enclosingScrollView: NSScrollView? { view.enclosingScrollView }
    var undoManager: UndoManager? { view.undoManager }
    var allowsUndo: Bool { view.allowsUndo }
    var isEditable: Bool { view.isEditable }
    var isPlainSourceEditor: Bool { !view.isRichText }
    var usesFindBar: Bool { view.usesFindBar }
    func selectedRange() -> NSRange { view.selectedRange() }
    func setSelectedRange(_ range: NSRange) { view.setSelectedRange(range) }
    func breakUndoCoalescing() { view.breakUndoCoalescing() }
    func doCommand(by selector: Selector) { view.doCommand(by: selector) }
    func insertText(_ value: String, replacementRange: NSRange) {
        view.insertText(value, replacementRange: replacementRange)
    }
}
