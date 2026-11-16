import AppKit
import ScribbitCore

/// AppKit owns editing, composition, clipboard, selection, find and undo.
/// The only extra editing command is leading-whitespace outdent.
final class NoteTextView: NSTextView {
    private var pendingScrollOrigin: CGPoint?

    /// One layout-owned restoration, not a delayed timer or ongoing scroll lock.
    func restoreViewport(_ origin: CGPoint?) {
        pendingScrollOrigin = origin
        if origin != nil { needsLayout = true }
    }

    override func layout() {
        super.layout()
        guard let origin = pendingScrollOrigin, let scroll = enclosingScrollView,
              scroll.contentSize.width > 0, scroll.contentSize.height > 0 else { return }
        pendingScrollOrigin = nil
        // Lay out the document before constraining an offset beyond the caret.
        // Respect whichever TextKit system AppKit gave this native text view.
        if let manager = textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        } else if let container = textContainer {
            layoutManager?.ensureLayout(for: container)
        }
        let clip = scroll.contentView
        var proposed = clip.bounds
        proposed.origin = origin
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scroll.reflectScrolledClipView(clip)
    }

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
