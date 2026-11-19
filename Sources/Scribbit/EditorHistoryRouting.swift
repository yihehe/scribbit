import AppKit

enum EditorHistoryRouting {
    /// WebKit may use a descendant view as its responder. Public view ancestry
    /// is sufficient; never inspect private WebKit view classes.
    static func ownsFocus(editor: NSView, responder: NSResponder?) -> Bool {
        guard let view = responder as? NSView else { return false }
        return view === editor || view.isDescendant(of: editor)
    }
}
