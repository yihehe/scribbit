import AppKit
import Testing
@testable import Scribbit

struct EditorHistoryRoutingTests {
    @MainActor @Test func historyFollowsEditorFocusNotActiveMode() {
        let root = NSView()
        let editor = NSView()
        let editorContent = NSView()
        let sheetField = NSTextView()
        root.addSubview(editor)
        editor.addSubview(editorContent)
        root.addSubview(sheetField)
        #expect(EditorHistoryRouting.ownsFocus(editor: editor, responder: editor))
        #expect(EditorHistoryRouting.ownsFocus(editor: editor, responder: editorContent))
        #expect(!EditorHistoryRouting.ownsFocus(editor: editor, responder: sheetField))
        #expect(!EditorHistoryRouting.ownsFocus(editor: editor, responder: root))
        #expect(!EditorHistoryRouting.ownsFocus(editor: editor, responder: nil))
        #expect(!EditorHistoryRouting.ownsFocus(editor: editor, responder: NSResponder()))
    }
}
