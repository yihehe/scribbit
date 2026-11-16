import AppKit
import SwiftUI
import Darwin
import ScribbitCore

@MainActor
private final class OutdentVetoDelegate: NSObject, NSTextViewDelegate {
    var calls = 0
    func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue],
                  replacementStrings: [String]?) -> Bool {
        calls += 1
        return false
    }
}

/// Opt-in GUI harness: only project-provided fixture paths, no AppDelegate,
/// UserDefaults writes, login registration, file pickers, or user notes.
@MainActor
final class SmokeTestDelegate: NSObject, NSApplicationDelegate {
    let output: URL
    var compatibilityIssues: [String] = []
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            do {
                try await run()
                guard compatibilityIssues.isEmpty else {
                    fputs("GUI_SMOKE_FAIL: compatibility blockers: \(compatibilityIssues.joined(separator: "; "))\n", stderr)
                    exit(1)
                }
                print("GUI_SMOKE_PASS"); exit(0)
            }
            catch { fputs("GUI_SMOKE_FAIL: \(error)\n", stderr); exit(1) }
        }
    }
    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "SmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private func editor(in view: NSView) -> EditorProbe? { EditorProbe.find(in: view) }
    private func settle() async { try? await Task.sleep(nanoseconds: 200_000_000) }
    private func finishTypingEvent(_ editor: EditorProbe) async throws {
        // A direct insertText fixture is not a keyboard event. Finish its undo
        // event before sending a separate command; no production code does this.
        guard let keyUp = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: editor.window?.windowNumber ?? 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 0) else {
            throw CocoaError(.featureUnsupported)
        }
        NSApp.postEvent(keyUp, atStart: false)
        await settle()
        try require(editor.undoManager?.groupingLevel == 0, "Harness failed to finish the preceding typing event")
    }
    private func snapshot(_ panel: NSPanel, name: String) throws {
        let view = panel.contentView!
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "SmokeTest", code: 2)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
    }
    private func verifyOutdent(_ textView: EditorProbe, model: NoteModel) async throws {
        let original = model.text
        let originalSelection = textView.selectedRange()
        let end = original.utf16.count
        NSApp.activate(ignoringOtherApps: true)
        textView.window?.makeKeyAndOrderFront(nil)
        textView.window?.makeFirstResponder(textView.view)
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.breakUndoCoalescing()
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        await settle()
        let suffixKinds = model.text.utf16.dropFirst(end).map { unit in
            unit == 9 ? "tab" : unit == 32 ? "space" : unit == 10 ? "newline" : "other"
        }
        try require(model.text == original + "\t",
                    "Tab no longer inserts a literal tab: suffixKinds=\(suffixKinds), nativeLength=\(textView.string.utf16.count), modelLength=\(model.text.utf16.count), expected=\(end + 1), editable=\(textView.isEditable), fieldEditor=\(textView.view.isFieldEditor), marked=\(textView.view.hasMarkedText()), responder=\(String(describing: textView.window?.firstResponder))")
        try await finishTypingEvent(textView)
        guard let backtab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: textView.window?.windowNumber ?? 0,
            context: nil, characters: "\u{19}", charactersIgnoringModifiers: "\u{19}", isARepeat: false, keyCode: 48) else {
            throw CocoaError(.featureUnsupported)
        }
        // Queue into this application only: exercise native key bindings and event undo boundaries, never an OS-global event.
        NSApp.postEvent(backtab, atStart: false)
        await settle()
        try require(model.text == original && textView.selectedRange() == NSRange(location: end, length: 0),
                    "Shift-Tab failed: textRestored=\(model.text == original), selection=\(textView.selectedRange()), expectedCaret=\(end)")
        textView.undoManager?.undo()
        await settle()
        try require(model.text == original + "\t", "Unindent undo failed: modelLength=\(model.text.utf16.count), editorLength=\(textView.string.utf16.count), expectedLength=\(end + 1)")
        textView.undoManager?.redo()
        await settle()
        try require(model.text == original, "Native redo did not reapply unindent")
        NSApp.postEvent(backtab, atStart: false)
        await settle()
        try require(model.text == original && textView.window?.firstResponder === textView.view,
                    "Shift-Tab on an unindented line moved focus or changed text")

        let indented = "\tAlpha 📝\n    Beta\n\tGamma"
        let unindented = "Alpha 📝\nBeta\nGamma"
        textView.breakUndoCoalescing()
        textView.insertText(indented, replacementRange: NSRange(location: end, length: 0))
        await settle()
        try await finishTypingEvent(textView)
        textView.setSelectedRange(NSRange(location: end, length: indented.utf16.count))
        textView.view.isEditable = false
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        try require(textView.string == original + indented, "Read-only outdent changed source")
        textView.view.isEditable = true
        let previousDelegate = textView.view.delegate
        let veto = OutdentVetoDelegate()
        textView.view.delegate = veto
        textView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
        textView.view.delegate = previousDelegate
        try require(veto.calls == 1 && textView.string == original + indented,
                    "Outdent ignored the delegate veto")
        NSApp.postEvent(backtab, atStart: false)
        await settle()
        try require(model.text == original + unindented, "Selected lines were not unindented through the binding")
        try require(textView.selectedRange() == NSRange(location: end, length: unindented.utf16.count),
                    "Unindent lost the multiline Unicode selection")
        textView.undoManager?.undo()
        await settle()
        try require(model.text == original + indented, "Multiline undo failed: modelLength=\(model.text.utf16.count), editorLength=\(textView.string.utf16.count), expectedLength=\((original + indented).utf16.count), modelEqualsOriginal=\(model.text == original), editorEqualsOriginal=\(textView.string == original)")
        textView.undoManager?.redo()
        await settle()
        try require(model.text == original + unindented, "Multiline unindent redo failed")
        // Restore the ordinary screenshot/save fixture through the same native path.
        textView.insertText(original, replacementRange: NSRange(location: 0, length: textView.string.utf16.count))
        textView.setSelectedRange(originalSelection)
        await settle()
        try require(model.text == original, "Indentation harness did not restore its fixture")
        print("INDENT_SMOKE_PASS: Tab/Shift-Tab key binding, caret, no-op focus, read-only/veto guards, multiline Unicode selection, atomic undo/redo, model binding")
    }
    private func run() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try await verifyPresenterLifecycle()
        let file = output.appendingPathComponent("fixture.md")
        try Data("# Scratch note\n\nA quiet place for **small ideas**.\n\n- Write here\n- Return to your work\n".utf8).write(to: file, options: .atomic)
        let model = NoteModel()
        let opened = await model.open(file)
        try require(opened, "Fixture did not open")
        let panel = NotePanel(contentRect: NSRect(x: 200, y: 200, width: 620, height: 460),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        let hosted = NSHostingView(rootView: NoteView(model: model,
            choose: {}, saveCopy: {}, reload: {}))
        let presenter = NotchPresenter(panel: panel, content: hosted)
        let display = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let geometry = NotchGeometry(screen: display, cameraWidth: 184, topInset: 32)
        presenter.configure(geometry)
        let reservedFrame = panel.frame
        let opening = Task { await presenter.reveal(takeFocus: false, reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        try require(presenter.shapeAnimation?.values?.count ?? 0 > 2, "Opening did not install silhouette keyframes")
        try require(presenter.opacityAnimation?.duration == 0.45, "Content reveal timing drifted")
        try require(presenter.arrivalAnchorDrift < 0.001, "Content arrival moved its top-center anchor")
        await opening.value
        try require(panel.frame == reservedFrame && !presenter.hasAnimations, "Opening resized window or left idle animations")
        await settle()
        guard let textView = editor(in: panel.contentView!) else {
            throw NSError(domain: "SmokeTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native editor missing"])
        }
        panel.makeFirstResponder(textView.view)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("\nAdded through editor.\n", replacementRange: textView.selectedRange())
        await settle()
        try require(model.text.contains("Added through editor."), "Native editor binding failed")
        try require(textView.allowsUndo && textView.usesFindBar && textView.isPlainSourceEditor, "Native editor configuration failed")
        try require(!model.controlsExpanded, "Controls did not start collapsed")
        try presenter.capture(to: output.appendingPathComponent("editor.png"))
        let viewport = textView.enclosingScrollView!.contentSize.height
        let selection = textView.selectedRange()
        let sourceBeforeDisclosure = model.text
        model.controlsExpanded = true
        await settle()
        try require(editor(in: panel.contentView!)?.view === textView.view, "Disclosure replaced the native editor")
        try require(textView.enclosingScrollView!.contentSize.height < viewport - 40, "Expanded controls did not occupy the bottom region")
        try require(textView.undoManager?.canUndo == true && textView.selectedRange() == selection, "Disclosure lost undo or selection")
        try presenter.capture(to: output.appendingPathComponent("controls-expanded.png"))
        model.controlsExpanded = false
        await settle()
        try require(model.text == sourceBeforeDisclosure, "Disclosure changed source text")
        try require(abs(textView.enclosingScrollView!.contentSize.height - viewport) < 1, "Collapsed controls still reserve expanded space")
        try await verifyOutdent(textView, model: model)
        try await verifyEditorInput(textView, model: model)
        if let raster = NSBitmapImageRep(data: try Data(contentsOf: output.appendingPathComponent("editor.png"))) {
            try require((raster.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1, "Snapshot lost transparent shoulders")
            try require((raster.colorAt(x: raster.pixelsWide / 2, y: 0)?.alphaComponent ?? 0) > 0.9, "Snapshot silhouette was inverted")
        }
        try MotionPreview.export(presenter: presenter, sourceURL: output.appendingPathComponent("editor.png"),
                                 destination: output.appendingPathComponent("motion-preview.gif"))
        model.preview = true
        await settle()
        try presenter.capture(to: output.appendingPathComponent("preview.png"))
        model.preview = false
        let closed = await model.close(keepPresentation: true)
        try require(closed, "Save-on-close failed")
        try require(!model.text.isEmpty, "Outgoing content cleared before its departure animation")
        await settle()
        guard let departingEditor = editor(in: panel.contentView!) else { throw CocoaError(.fileReadUnknown) }
        try require(!departingEditor.isEditable, "Departing editor still accepted unsaved keystrokes")
        let collapsing = Task { await presenter.dismiss(reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        try require(presenter.shapeAnimation != nil && presenter.opacityAnimation?.duration == 0.16, "Collapse animation missing")
        await collapsing.value
        model.clearClosedPresentation()
        try require(!panel.isVisible && !presenter.hasAnimations, "Collapse left a window or animation behind")
        let saved = try String(contentsOf: file, encoding: .utf8)
        try require(saved.contains("Added through editor."), "Saved file missing native edit")
        try Data("External change\n".utf8).write(to: file, options: .atomic)
        let reopened = await model.open(file)
        try require(reopened && model.text == "External change\n", "Reopen did not refresh disk")
        presenter.animationSpeed = 2
        let fast = Task { await presenter.reveal(takeFocus: false, reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        let normalPlan = NotchMotion.Plan(from: geometry.collapsedSize, to: geometry.expandedSize)
        try require(abs((presenter.shapeAnimation?.duration ?? 0) - normalPlan.duration / 2) < 0.001, "2x did not scale the silhouette clock")
        try require(presenter.opacityAnimation?.duration == 0.225, "2x did not scale content reveal")
        presenter.animationSpeed = 0.5
        try require(presenter.opacityAnimation?.duration == 0.225, "Changing speed retimed an in-flight transition")
        await fast.value
        let slow = Task { await presenter.dismiss(reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        try require(presenter.opacityAnimation?.duration == 0.32, "0.5x did not scale departure")
        await slow.value
        let reduced = Task { await presenter.reveal(takeFocus: false, reduceMotion: true) }
        while !presenter.isTransitioning { await Task.yield() }
        try require(presenter.shapeAnimation == nil && presenter.opacityAnimation?.duration == 0.14, "Speed setting overrode Reduce Motion")
        await reduced.value
        model.text = "My conflicting edit"
        try Data("Other writer\n".utf8).write(to: file, options: .atomic)
        let conflictClosed = await model.close()
        try require(!conflictClosed && model.isOpen && model.error != nil, "Conflict lost open buffer")
        await settle()
        try presenter.capture(to: output.appendingPathComponent("conflict.png"))
        presenter.showsRestingWing = true
        let wingClosing = Task { await presenter.dismiss(reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        let expectedWing = geometry.indicator.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
        let closingPath = presenter.shapeAnimation!.values!.last! as! CGPath
        try require(closingPath.boundingBoxOfPath == expectedWing, "Collapse did not join the left resting wing")
        await wingClosing.value
        let wingOpening = Task { await presenter.reveal(takeFocus: false, reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        let openingPath = presenter.shapeAnimation!.values!.first! as! CGPath
        try require(openingPath.boundingBoxOfPath == expectedWing, "Opening jumped from the wing to a bare notch")
        await wingOpening.value
        let restingPanel = NSPanel(contentRect: geometry.indicator, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        restingPanel.isReleasedWhenClosed = false
        restingPanel.isOpaque = false
        restingPanel.backgroundColor = .clear
        restingPanel.appearance = NSAppearance(named: .darkAqua)
        let resting = RestingNotchView(geometry: geometry)
        restingPanel.contentView = resting
        restingPanel.orderFrontRegardless()
        await settle()
        try resting.capture(to: output.appendingPathComponent("left-wing.png"))
        restingPanel.orderOut(nil)
        print("CONTROLS_SMOKE_PASS: default collapse, bottom disclosure, viewport recovery, undo/selection, speed clocks, Reduce Motion, asymmetric wing endpoints")
        // A display change in flight must resolve its waiter exactly once.
        let moving = Task { await presenter.dismiss(reduceMotion: false) }
        while !presenter.isTransitioning { await Task.yield() }
        presenter.configure(geometry)
        await moving.value
        try require(!panel.isVisible && !presenter.hasAnimations, "Display change left stale collapse callbacks")
        print("ANIMATION_SMOKE_PASS: stable frame, opening/collapse keyframes, content timing, Reduce Motion, display-change completion")
        try Data("Shell fixture".utf8).write(to: output.appendingPathComponent("shell-fixture.md"), options: .atomic)
        let shell = AppDelegate(isolated: true)
        try await shell.runIsolatedShellChecks(file: output.appendingPathComponent("shell-fixture.md"))
        var before = rusage(), after = rusage()
        getrusage(RUSAGE_SELF, &before)
        try await Task.sleep(nanoseconds: 3_000_000_000)
        getrusage(RUSAGE_SELF, &after)
        func cpu(_ value: rusage) -> Double {
            Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) +
                Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
        }
        let report = "Hidden harness idle interval: 3 s\nCPU seconds: \(cpu(after) - cpu(before))\nPeak RSS bytes: \(after.ru_maxrss)\nHarness excludes live AppDelegate event monitors and login services. Not a full app benchmark.\n"
        try report.write(to: output.appendingPathComponent("resources.txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
