import AppKit
import WebKit
import ScribbitCore

/// Opt-in integration harness using the packaged JS and a real WKWebView.
/// It never creates AppDelegate, reads preferences, changes login registration,
/// uses the system clipboard, or opens a user-selected file.
@MainActor
final class RichEditorSmoke: NSObject, NSApplicationDelegate {
    let output: URL
    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            fputs("RICH_EDITOR_SMOKE_FAIL: harness exceeded 60 seconds\n", stderr)
            exit(1)
        }
        Task {
            do {
                try await run()
                print("RICH_EDITOR_SMOKE_PASS")
                exit(0)
            } catch {
                fputs("RICH_EDITOR_SMOKE_FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "RichEditorSmoke", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private func js(_ editor: RichMarkdownEditor, _ script: String,
                    arguments: [String: Any] = [:]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            editor.web.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) {
                continuation.resume(with: $0.map { Optional($0) })
            }
        }
    }

    private func paste(_ text: String, into editor: RichMarkdownEditor) async throws {
        _ = try await js(editor, """
            const root = document.querySelector(".ProseMirror");
            root.focus();
            const range = document.createRange();
            range.selectNodeContents(root);
            range.collapse(false);
            const selection = window.getSelection();
            selection.removeAllRanges(); selection.addRange(range);
            const event = new Event("paste", {bubbles: true, cancelable: true});
            Object.defineProperty(event, "clipboardData", {value: {
              files: [], getData: kind => kind === "text/plain" ? text : ""
            }});
            root.dispatchEvent(event);
            """, arguments: ["text": text])
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !condition() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, message)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func run() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = output.appendingPathComponent("note-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let original = "# Disposable\n\n- first\n- second\n"
        try Data(original.utf8).write(to: fixture, options: .withoutOverwriting)
        let editor = RichMarkdownEditor()
        let panel = NotePanel(contentRect: CGRect(x: 150, y: 150, width: 640, height: 420),
                              styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = editor.createView()
        defer { editor.invalidate(); panel.orderOut(nil) }
        panel.orderFrontRegardless()
        let model = NoteModel()
        model.captureEditor = { try await editor.capture(inspectionOnly: $0) }
        model.finishEditor = { editor.finish($0, source: $1) }
        model.invalidateEditor = { editor.invalidate() }
        editor.changed = { model.editorDidChange($0) }
        editor.failed = { model.error = $0 }
        try require(await model.open(fixture), "Fixture open failed")
        await model.prepareEditor { await editor.prepare(source: model.text, url: fixture) }
        try require(editor.active, "Rich import failed: \(editor.fallbackReason ?? "unknown")")
        await model.save()
        try require(model.error == nil, "Unchanged capture failed")
        try require(try Data(contentsOf: fixture) == Data(original.utf8), "Clean capture rewrote source")
        print("RICH_BRIDGE_UNCHANGED_PASS")

        // Paste a complete list into an empty document. At a heading caret,
        // ProseMirror may legitimately fit a one-item slice as inline content.
        try require(await model.changeEditorMode(toRich: false, importRich: { _, _ in false },
            activateSource: { editor.deactivateToSource() }), "Clipboard fixture source switch failed")
        model.text = ""
        try require(await model.changeEditorMode(toRich: true, importRich: { source, url in
            await editor.prepare(source: source, url: url)
            return editor.active
        }, activateSource: {}), "Clipboard fixture rich switch failed")
        let clipboardPassed = try await js(editor, """
            const root = document.querySelector(".ProseMirror");
            root.focus();
            const formats = {
              "text/html": "<ul><li><p><strong>clipboard-marker</strong></p></li></ul>",
              "text/plain": "clipboard-marker"
            };
            const paste = new Event("paste", {bubbles: true, cancelable: true});
            Object.defineProperty(paste, "clipboardData", {value: {
              files: [], getData: kind => formats[kind] ?? ""
            }});
            root.dispatchEvent(paste);
            return {
              ok: [...root.querySelectorAll("li strong")].some(
                item => item.textContent === "clipboard-marker"),
              prevented: paste.defaultPrevented, editable: root.contentEditable,
              marker: root.textContent.includes("clipboard-marker"),
              lists: root.querySelectorAll("li").length,
              strong: root.querySelectorAll("strong").length
            };
            """) as? [String: Any]
        try require(clipboardPassed?["ok"] as? Bool == true, "Rich HTML paste lost structure: \(clipboardPassed ?? [:])")
        await model.save()
        try require(model.error == nil, "Pasted list failed snapshot validation")
        print("RICH_BRIDGE_CLIPBOARD_PASS")

        try await paste("appended", into: editor)
        await model.save()
        try require(model.error == nil && model.text.contains("appended"), "Rich edit failed to reach native save")
        try require(try Data(contentsOf: fixture) == Data(model.text.utf8), "Saved bytes differ from accepted source")

        let saved = model.text
        try require(await model.changeEditorMode(toRich: false, importRich: { _, _ in false },
            activateSource: { editor.deactivateToSource() }), "Rich to Source failed")
        try require(!editor.active && model.text == saved && !model.isDirty, "Mode switch changed saved bytes")
        model.text += "\nSource-mode edit\n"
        try require(await model.changeEditorMode(toRich: true, importRich: { source, url in
            await editor.prepare(source: source, url: url)
            return editor.active
        }, activateSource: {}), "Source to Rich failed")
        try require(editor.active && model.isDirty, "Import moved the disk baseline")
        try require(try Data(contentsOf: fixture) == Data(saved.utf8), "Mode switch wrote the file")
        print("RICH_BRIDGE_MODES_PASS")

        try await paste("retained-conflict", into: editor)
        let external = Data("External replacement\n".utf8)
        try external.write(to: fixture, options: .atomic)
        try require(await !model.close(), "Conflict incorrectly closed the editor")
        try require(model.isOpen && model.isDirty && editor.active, "Conflict did not retain the rich draft")
        try require(try Data(contentsOf: fixture) == external, "Conflict overwrote external bytes")
        print("RICH_BRIDGE_SAVE_CONFLICT_PASS")

        await model.reload()
        await model.prepareEditor { await editor.prepare(source: model.text, url: fixture) }
        try require(editor.active && model.error == nil && !model.isDirty, "Explicit reload failed")
        try require(await model.close(), "Clean close failed")
        editor.releaseClosedDocument()
        let cleared = try await js(editor, "return document.querySelector('.ProseMirror').textContent;") as? String
        try require(cleared == "", "Closed document retained hidden content")
        model.editorDidChange(false)
        model.error = nil
        // Exercise the delegate boundary deterministically, without killing a
        // shared WebKit process. This is not OS crash-delivery acceptance.
        editor.webViewWebContentProcessDidTerminate(editor.web)
        try require(!editor.needsRecovery && !model.pendingEditorChanges && model.error == nil,
                    "Inactive WebKit termination dirtied the native/hidden note")
        print("RICH_BRIDGE_INACTIVE_TERMINATION_PASS")

        await editor.prepare(source: "Source only", url: fixture.deletingPathExtension().appendingPathExtension("txt"))
        try require(!editor.active, "Plain-text file did not use source fallback")
        await editor.prepare(source: "Valid\n", url: fixture)
        try require(editor.active, "Rich editor could not reopen after fallback")
        _ = try await js(editor, """
            window.originalFlush = window.scribbit.flush;
            window.scribbit.flush = (id, inspection, committed) => {
              window.webkit.messageHandlers.richEditor.postMessage({
                type: "snapshot", id, revision: 100,
                token: new URL(location.href).searchParams.get("token"),
                generation: committed.generation,
                document: {type: "unsupported-fixture-node"}
              });
            };
            """)
        do {
            _ = try await editor.capture()
            throw NSError(domain: "RichEditorSmoke", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid snapshot was accepted"])
        } catch {
            try require(error.localizedDescription == "Invalid rich document.",
                        "Invalid snapshot did not fail immediately with validation error: \(error)")
        }
        _ = try await js(editor, "window.scribbit.flush = window.originalFlush;")
        let source = try await editor.capture()
        try require(source == "Valid\n", "Editor did not recover after invalid response")
        editor.finish(.retained, source: source ?? "")
        print("RICH_BRIDGE_INVALID_REPLY_PASS")

        try await paste("checkpoint-marker", into: editor)
        let acknowledged = try await editor.capture()
        editor.finish(.retained, source: acknowledged ?? "")
        editor.webViewWebContentProcessDidTerminate(editor.web)
        try require(editor.needsRecovery, "Active draft did not enter explicit recovery")
        editor.restore()
        editor.restore() // Repeated clicks must not replace a checked continuation.
        try await waitUntil("Checkpoint restore did not finish") { !editor.needsRecovery }
        let recovered = try await editor.capture()
        try require(recovered == acknowledged, "Acknowledged checkpoint did not survive page recreation")
        editor.finish(.retained, source: recovered ?? "")
        print("RICH_BRIDGE_RECOVERY_PASS")

        // A missing restore acknowledgement must allow retry, not strand the
        // recovery button. Use the real five-second deadline, not a test-only one.
        editor.webViewWebContentProcessDidTerminate(editor.web)
        try await waitUntil("Recovery page did not load") { !editor.web.isLoading }
        _ = try await js(editor, """
            window.originalRestore = window.scribbit.restore;
            window.scribbit.restore = () => {};
            """)
        editor.restore()
        try await waitUntil("Restore timeout was not reported") {
            model.error?.contains("checkpoint restore timed out") == true
        }
        try require(editor.needsRecovery, "Timeout discarded recovery state")
        _ = try await js(editor, "window.scribbit.restore = window.originalRestore;")
        editor.restore()
        try await waitUntil("Retry after restore timeout did not finish") { !editor.needsRecovery }
        let retried = try await editor.capture()
        try require(retried == acknowledged, "Restore timeout/retry lost the checkpoint")
        editor.finish(.retained, source: retried ?? "")
        print("RICH_BRIDGE_RESTORE_RETRY_PASS")

        await editor.prepare(source: "- bullet\n\n3. numbered\n\n- [ ] task\n- [x] done\n", url: fixture)
        try require(editor.active, "List cursor fixture import failed")
        func markerCursors() async throws -> [String] {
            try await js(editor, """
                await new Promise(resolve => requestAnimationFrame(resolve));
                const root = document.querySelector(".ProseMirror");
                return ["bullet", "ordered", "unchecked", "checked"].map(kind => {
                  const marker = root.querySelector(".label." + kind);
                  return marker ? getComputedStyle(marker).cursor : "missing";
                });
                """) as? [String] ?? []
        }
        try require(try await markerCursors() == ["text", "text", "pointer", "pointer"],
                    "Editable list markers have stale disabled cursors")
        editor.setReadOnly(true)
        try require(try await markerCursors() == Array(repeating: "not-allowed", count: 4),
                    "Locked list markers lost disabled cursors")
        _ = try await js(editor, """
            document.querySelector(".label.unchecked").parentElement.dispatchEvent(
              new MouseEvent("pointerdown", {bubbles: true, cancelable: true}));
            """)
        let lockedSource = try await editor.capture()
        try require(lockedSource?.contains("[ ] task") == true, "Read-only task click changed the document")
        editor.finish(.retained, source: lockedSource ?? "")
        editor.setReadOnly(false)
        try require(try await markerCursors() == ["text", "text", "pointer", "pointer"],
                    "Unlock did not restore marker cursors")
        _ = try await js(editor, """
            document.querySelector(".label.unchecked").parentElement.dispatchEvent(
              new MouseEvent("pointerdown", {bubbles: true, cancelable: true}));
            """)
        let toggledSource = try await editor.capture()
        try require(toggledSource?.contains("[x] task") == true, "Editable task checkbox no longer toggles")
        editor.finish(.retained, source: toggledSource ?? "")
        try require(try await markerCursors() == ["text", "text", "missing", "pointer"],
                    "Save settlement restored stale cursor styling")
        print("RICH_LIST_CURSOR_PASS")

        await editor.prepare(source: "- &#x20;\n", url: fixture)
        try require(editor.active, "Empty-list whitespace fixture import failed")
        _ = try await js(editor, """
            const root = document.querySelector(".ProseMirror");
            root.focus();
            const paste = new Event("paste", {bubbles: true, cancelable: true});
            Object.defineProperty(paste, "clipboardData", {value: {
              files: [], getData: kind => kind === "text/plain" ? " " : ""
            }});
            root.dispatchEvent(paste);
            """)
        let spaced = try await editor.capture()
        try require(spaced?.contains("&#x20;") == true, "List-item space failed to export losslessly")
        editor.finish(.saved, source: spaced ?? "")
        await editor.prepare(source: spaced ?? "", url: fixture)
        try require(editor.active, "Space-only list item failed to reopen")
        let content = try await js(editor, """
            return document.querySelector(".list-item .children p")?.textContent;
            """) as? String
        try require(content == "  ", "List-item spaces were trimmed on reopen")
        print("RICH_LIST_SPACE_PASS")
    }
}
