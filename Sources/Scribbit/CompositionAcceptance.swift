import AppKit

/// Contract regressions, run against the native editor in the disposable GUI harness.
/// A failing library contract stays a failed gate, not an expected-success test.
extension SmokeTestDelegate {
    @MainActor
    func verifyCompositionContracts(_ editor: EditorProbe, model: NoteModel) async throws {
        let client: any NSTextInputClient = editor.view
        let original = model.text
        var reports: [[String: Any]] = []
        func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }
        func reset(_ source: String, selection: NSRange) async {
            model.text = source
            await settle()
            editor.setSelectedRange(selection)
            editor.breakUndoCoalescing()
        }
        func record(_ name: String, expected: String, expectedSelection: NSRange? = nil) {
            let sourceMatches = editor.string.utf8.elementsEqual(expected.utf8)
            let bindingMatches = model.text.utf8.elementsEqual(expected.utf8)
            let selectionMatches = expectedSelection.map { editor.selectedRange() == $0 } ?? true
            let passed = sourceMatches && bindingMatches && selectionMatches && !client.hasMarkedText()
            reports.append([
                "case": name, "passed": passed, "expected": expected,
                "actual": editor.string, "binding": model.text,
                "undo_available": editor.undoManager?.canUndo == true,
                "has_marked_text": client.hasMarkedText(),
                "selection": NSStringFromRange(editor.selectedRange()),
                "expected_selection": expectedSelection.map(NSStringFromRange) ?? "not asserted"
            ])
            if !passed { compatibilityIssues.append("Composition contract: \(name)") }
        }

        // Finalization without replacement must accept visible preedit. A second
        // call must be harmless; the suffix detects accidental range shifting.
        await reset("left|right", selection: NSRange(location: 5, length: 0))
        client.setMarkedText("え😀", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        client.unmarkText()
        client.unmarkText()
        await settle()
        record("unmark accepts Unicode preedit in middle; repeated unmark is a no-op",
               expected: "left|え😀right", expectedSelection: NSRange(location: 8, length: 0))

        // Explicit commit must still replace preedit, not insert a second copy.
        await reset("A|Z", selection: NSRange(location: 2, length: 0))
        client.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        client.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertText("仮名", replacementRange: client.markedRange())
        await settle()
        record("updated preedit explicit commit preserves suffix", expected: "A|仮名Z")

        // An IME may start by replacing selected source, not just at a caret.
        await reset("AoldZ", selection: NSRange(location: 1, length: 3))
        client.setMarkedText("新", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertText("新", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle()
        record("default-range composition replaces selection", expected: "A新Z")

        // Cancellation is an empty replacement, NOT acceptance via unmarkText.
        await reset("A|Z", selection: NSRange(location: 2, length: 0))
        client.setMarkedText("cancel", selectedRange: NSRange(location: 6, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        client.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        client.unmarkText()
        await settle()
        record("empty marked replacement cancels preedit", expected: "A|Z")

        // Outdent must not edit preedit. Chrome updates must not replace it.
        await reset("\tA|Z", selection: NSRange(location: 3, length: 0))
        client.setMarkedText("え", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        model.controlsExpanded.toggle()
        await settle()
        guard editor.string == "\tA|えZ", client.hasMarkedText() else {
            throw NSError(domain: "CompositionAcceptance", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Outdent or chrome update modified live preedit"])
        }
        client.unmarkText()
        await settle()
        record("outdent and chrome update preserve live preedit", expected: "\tA|えZ")
        model.controlsExpanded = false

        try JSONSerialization.data(withJSONObject: ["engine": "native", "cases": reports],
                                   options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("composition-regressions.json"))
        let failures = reports.filter { $0["passed"] as? Bool == false }.count
        print("COMPOSITION_CONTRACTS: \(reports.count - failures)/\(reports.count) passed for native")
        model.text = original
        await settle()
    }
}
