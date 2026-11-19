import Foundation
import ScribbitCore

extension RichEditorSmoke {
    /// Shares fixture data with bundled-JS tests, but uses an independent DOM
    /// oracle and actual native coordinated save/close/reopen. Edits are synthetic
    /// text-node mutations observed by ProseMirror, not physical keyboard input.
    @MainActor
    func verifyMarkdownParity(editor: RichMarkdownEditor) async throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/markdown-parity.json")
        guard let data = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any],
              let contexts = data["contexts"] as? [[String: Any]],
              let offsets = data["nativeOffsets"] as? [Int],
              let insertion = data["nativeInsertion"] as? String else {
            throw RichMarkdownPolicy.failure("Invalid parity fixtures.")
        }
        let observe = """
            const root = document.querySelector(".ProseMirror");
            const block = [...root.querySelectorAll("p,h1,h2,h3,h4,h5,h6")]
              .find(element => element.textContent.includes("first"));
            if (!block) throw new Error("Missing fixture textblock");
            const runs = [];
            function visit(node) {
              if (node.nodeType === Node.ELEMENT_NODE) {
                if (node.matches(".ProseMirror-trailingBreak")) return;
                if (node.matches("br,span[data-type='hardbreak']")) {
                  runs.push({break: node.getAttribute("data-is-inline") === "true" ? "soft" : "hard"});
                  return;
                }
              }
              if (node.nodeType === Node.TEXT_NODE && node.nodeValue) {
                const marks = [];
                for (let element = node.parentElement; element && element !== block; element = element.parentElement) {
                  const type = {STRONG:"strong", B:"strong", EM:"emphasis", I:"emphasis",
                    DEL:"strike_through", S:"strike_through", CODE:"inlineCode", A:"link"}[element.tagName];
                  if (type === "link") marks.push({type, href:element.getAttribute("href"), title:element.getAttribute("title")});
                  else if (type) marks.push({type});
                }
                marks.sort((a,b) => a.type.localeCompare(b.type));
                const previous = runs.at(-1);
                if (previous?.text !== undefined && JSON.stringify(previous.marks) === JSON.stringify(marks))
                  previous.text += node.nodeValue;
                else runs.push({text:node.nodeValue, marks});
              }
              for (const child of node.childNodes) visit(child);
            }
            """
        func sameJSON(_ left: Any, _ right: Any) throws -> Bool {
            try JSONSerialization.data(withJSONObject: left, options: [.sortedKeys, .withoutEscapingSlashes])
                == JSONSerialization.data(withJSONObject: right, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        var completed = 0
        for context in contexts where context["native"] as? Bool == true {
            guard let id = context["id"] as? String, let source = context["source"] as? String,
                  let initialRuns = context["runs"] as? [[String: Any]] else {
                throw RichMarkdownPolicy.failure("Invalid native parity case.")
            }
            for offset in offsets {
                let file = output.appendingPathComponent("parity-\(UUID().uuidString).md")
                try Data(source.utf8).write(to: file, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: file) }
                let model = NoteModel()
                model.captureEditor = { [weak editor] in try await editor?.capture(inspectionOnly: $0) }
                model.finishEditor = { [weak editor] in editor?.finish($0, source: $1) }
                model.invalidateEditor = { [weak editor] in editor?.invalidate() }
                editor.changed = { [weak model] in model?.editorDidChange($0) }
                editor.failed = { [weak model] in model?.error = $0 }
                try require(await model.open(file), "\(id): fixture open failed")
                await model.prepareEditor { await editor.prepare(source: model.text, url: file) }
                try require(editor.active, "\(id): import rejected")
                let before = try await js(editor, observe + "visit(block); return runs;") ?? []
                try require(try sameJSON(before, initialRuns), "\(id): initial DOM differs from fixture")
                var expected = initialRuns
                let text = "first" as NSString
                expected[0]["text"] = text.substring(to: offset) + insertion + text.substring(from: offset)
                let edited = try await js(editor, observe + """
                    const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
                    let target;
                    while (walker.nextNode()) {
                      if (walker.currentNode.nodeValue.includes("first")) { target = walker.currentNode; break; }
                    }
                    if (!target) throw new Error("Missing edit target");
                    const index = target.nodeValue.indexOf("first") + offset;
                    target.nodeValue = target.nodeValue.slice(0,index) + insertion + target.nodeValue.slice(index);
                    target.parentElement.dispatchEvent(new InputEvent("input", {bubbles:true, inputType:"insertText", data:insertion}));
                    visit(block); return runs;
                    """, arguments: ["offset": offset, "insertion": insertion]) ?? []
                try require(try sameJSON(edited, expected), "\(id): edit did not match fixture")
                try await waitUntil("\(id): DOM edit was not acknowledged") { model.pendingEditorChanges }
                await model.save()
                try require(model.error == nil && !model.isDirty, "\(id): native save failed")
                let saved = try Data(contentsOf: file)
                try require(saved == Data(model.text.utf8), "\(id): disk differs from accepted source")
                try require(await model.close(), "\(id): close failed")
                editor.releaseClosedDocument()
                try require(await model.open(file), "\(id): disk reopen failed")
                await model.prepareEditor { await editor.prepare(source: model.text, url: file) }
                try require(editor.active, "\(id): reopened source rejected")
                let reopened = try await js(editor, observe + "visit(block); return runs;") ?? []
                try require(try sameJSON(reopened, expected), "\(id): reopened DOM lost text/marks/breaks")
                await model.save()
                try require(model.error == nil && (try Data(contentsOf: file)) == saved, "\(id): clean save changed bytes")
                try require(await model.close(), "\(id): final close failed")
                editor.releaseClosedDocument()
                completed += 1
            }
        }
        try require(completed == 12, "Native parity fixture count changed without updating the gate")
        print("MARKDOWN_PARITY_NATIVE_PASS: \(completed) shared cases through actual disk save/close/reopen")
    }
}
