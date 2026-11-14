import AppKit
import SwiftUI
import ScribbitCore

struct NoteView: View {
    @ObservedObject var model: NoteModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let choose: () -> Void
    let close: () -> Void
    let saveCopy: () -> Void
    let reload: () -> Void
    var speedChanged: (Double) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if model.preview {
                ScrollView {
                    Text((try? AttributedString(markdown: model.text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(model.text))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
            } else {
                NativeEditor(text: $model.text)
            }
            // Recovery never lives inside a collapsed disclosure.
            if let error = model.error {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    HStack {
                        Button("Retry Save") { Task { await model.save() } }
                        Button("Save a Copy…", action: saveCopy)
                        Button("Reload from Disk…", action: reload)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.controlsExpanded {
                Divider()
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.filename).font(.headline).lineLimit(1)
                            Text(model.isDirty ? "Unsaved edits · saves when closed" : "File-backed note")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.pinned.toggle() } label: {
                            Image(systemName: model.pinned ? "pin.fill" : "pin")
                        }.help(model.pinned ? "Unpin: close when pointer leaves" : "Pin note open")
                        Button(action: choose) { Image(systemName: "folder") }.help("Choose another file")
                        Button { model.preview.toggle() } label: {
                            Image(systemName: model.preview ? "pencil" : "eye")
                        }.help(model.preview ? "Edit source" : "Preview Markdown")
                        Button("Done", action: close)
                    }
                    HStack(spacing: 10) {
                        Text("Animation speed").font(.caption)
                        Slider(value: Binding(get: { model.animationSpeed }, set: { value in
                            model.animationSpeed = AnimationSpeed.normalized(value)
                            speedChanged(model.animationSpeed)
                        }), in: AnimationSpeed.range, step: 0.25)
                            .accessibilityLabel("Animation speed")
                        Text(AnimationSpeed.label(model.animationSpeed))
                            .font(.caption.monospacedDigit()).frame(width: 34, alignment: .trailing)
                    }
                    HStack {
                        Text(model.preview ? "Read-only preview · inline Markdown" : "UTF-8 · ⌘S to save")
                        Spacer()
                        Text("Esc / ⌘↵ to close")
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                .accessibilityIdentifier("noteControls")
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AnimationSpeed.duration(0.16, rate: model.animationSpeed))) {
                    model.controlsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    if model.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Image(systemName: model.controlsExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.controlsExpanded ? "Hide note controls" : "Show note controls")
            .accessibilityLabel(model.controlsExpanded ? "Hide note controls" : "Show note controls")
            .accessibilityIdentifier("toggleNoteControls")
        }
        .disabled(model.isBusy || !model.isOpen)
        .overlay { if model.isBusy { ProgressView("Updating file…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .background(Color(white: 0.035))
    }
}

struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoteTextView.scrollableTextView()
        let editor = scroll.documentView as! NSTextView
        editor.isRichText = false
        editor.isEditable = context.environment.isEnabled
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textContainerInset = NSSize(width: 16, height: 16)
        editor.backgroundColor = NSColor(white: 0.035, alpha: 1)
        editor.textColor = .textColor
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.isHorizontallyResizable = false
        editor.delegate = context.coordinator
        context.coordinator.synchronize(text, into: editor)
        context.coordinator.observeHistory(of: editor)
        editor.setAccessibilityLabel("Note text")
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let editor = scroll.documentView as! NSTextView
        editor.isEditable = context.environment.isEnabled
        context.coordinator.synchronize(text, into: editor)
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        coordinator.stopObservingHistory()
        editor.isEditable = false
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.delegate = nil
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        private var lastModelText: String?
        private var isSynchronizing = false
        private var historyObservers: [NSObjectProtocol] = []
        init(_ parent: NativeEditor) { self.parent = parent }
        deinit { historyObservers.forEach(NotificationCenter.default.removeObserver) }
        func observeHistory(of editor: NSTextView) {
            stopObservingHistory()
            // Programmatic/native history can change storage without delivering
            // textDidChange. Publish the final source after that transaction.
            for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                historyObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self, weak editor] notification in
                    MainActor.assumeIsolated {
                        guard let self, let editor,
                              let manager = notification.object as? UndoManager,
                              manager === editor.undoManager else { return }
                        self.publish(editor)
                    }
                })
            }
        }
        func stopObservingHistory() {
            historyObservers.forEach(NotificationCenter.default.removeObserver)
            historyObservers.removeAll()
        }
        func synchronize(_ value: String, into editor: NSTextView) {
            // A chrome-only SwiftUI update must not overwrite AppKit's preedit
            // buffer, which can differ from the last committed model value.
            if let lastModelText, lastModelText.utf8.elementsEqual(value.utf8) { return }
            isSynchronizing = true
            defer { isSynchronizing = false }
            let selection = editor.selectedRange()
            editor.unmarkText()
            editor.string = value
            let location = min(selection.location, value.utf16.count)
            editor.setSelectedRange(NSRange(location: location,
                length: min(selection.length, value.utf16.count - location)))
            editor.undoManager?.removeAllActions()
            lastModelText = value
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            publish(editor)
        }
        private func publish(_ editor: NSTextView) {
            guard !isSynchronizing else { return }
            lastModelText = editor.string
            if !parent.text.utf8.elementsEqual(editor.string.utf8) {
                parent.text = editor.string
            }
        }
    }
}
