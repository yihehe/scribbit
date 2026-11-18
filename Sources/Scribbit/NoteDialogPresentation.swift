import AppKit

/// Native sheets inherit the notch parent's ordering band; standalone modal
/// windows at AppKit's default modalPanel level would sit underneath it.
enum NoteDialogPresentation {
    static func sheetLevel(parent: NSWindow.Level) -> NSWindow.Level { parent }
}
