import AppKit
import ScribbitCore

/// Additional opt-in checks on the real component; named/private pasteboards only.
extension SmokeTestDelegate {
    @MainActor
    func verifyEditorInput(_ editor: EditorProbe, model: NoteModel) async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "EditorAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }
        let original = model.text
        for sample in ["\t😀\r\ncafe\u{301}\r\n", "\u{feff}BOM\rCR\nLF\u{2028}line\u{2029}paragraph\n", ""] {
            model.text = sample
            await settle()
            try check(Data(editor.string.utf8) == Data(sample.utf8), "Editor load changed source bytes")
            editor.insertText("!", replacementRange: NSRange(location: sample.utf16.count, length: 0))
            await settle()
            try check(Data(model.text.utf8) == Data((sample + "!").utf8), "Editor binding changed newline/Unicode bytes")
        }
        model.text = original
        await settle()
        let client: any NSTextInputClient = editor.view
        let end = original.utf16.count
        editor.setSelectedRange(NSRange(location: end, length: 0))
        client.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: end, length: 0))
        try check(client.hasMarkedText(), "Marked-text input was not established")
        let marked = client.markedRange()
        editor.insertText("あ", replacementRange: marked)
        await settle()
        try check(!client.hasMarkedText() && model.text == original + "あ", "Marked-text commit lost or duplicated input")
        model.text = original
        await settle()
        editor.setSelectedRange(NSRange(location: end, length: 0))
        client.setMarkedText("い", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertText("い", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()
        try check(!client.hasMarkedText() && model.text == original + "い", "Default-range marked commit failed")
        model.text = original
        await settle()

        editor.setSelectedRange(NSRange(location: end, length: 0))
        client.setMarkedText("え", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        client.unmarkText()
        await settle()
        let unmarkPreservedText = editor.string == original + "え"
        let unmarkReport: [String: Any] = ["engine": "native", "unmark_only_preserved_visible_text": unmarkPreservedText,
                                          "unmark_only_updated_binding": model.text == original + "え"]
        try JSONSerialization.data(withJSONObject: unmarkReport, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("marked-text-compatibility.json"))
        if !unmarkPreservedText {
            compatibilityIssues.append("Unmark-only input finalization removes preedit text")
            print("UNMARK_COMPATIBILITY_LIMITATION: visible preedit was removed instead of accepted")
        }
        model.text = original
        await settle()

        try await verifyCompositionContracts(editor, model: model)

        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        try check(editor.view.tryToPerform(#selector(NSTextView.performFindPanelAction(_:)), with: find), "Find command not handled")
        await settle()
        try check(editor.enclosingScrollView?.isFindBarVisible == true, "Find bar did not show")
        find.tag = NSTextFinder.Action.hideFindInterface.rawValue
        _ = editor.view.tryToPerform(#selector(NSTextView.performFindPanelAction(_:)), with: find)
        await settle()
        try check(editor.enclosingScrollView?.isFindBarVisible == false, "Find bar did not hide")

        guard let url = model.url else { throw CocoaError(.fileReadUnknown) }
        let closed = await model.close(keepPresentation: true)
        try check(closed, "Read-only test could not save fixture")
        await settle()
        try check(!editor.isEditable, "Closed editor remained editable")
        model.clearClosedPresentation()
        await settle()
        let reopened = await model.open(url)
        await settle()
        try check(reopened && model.text == original && editor.isEditable, "Read-only freeze failed to recover after reopen")
        print("EDITOR_INPUT_SMOKE_PASS: exact UTF-8/newlines, marked-text API commit, find, read-only freeze/reopen")
    }
}
