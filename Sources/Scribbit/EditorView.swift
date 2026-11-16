import AppKit
import SwiftUI
import ScribbitCore

struct NoteView: View {
    @ObservedObject var model: NoteModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let choose: () -> Void
    let saveCopy: () -> Void
    let reload: () -> Void
    var create: () -> Void = {}
    var showSettings: (NSButton) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if model.showsWelcome {
                VStack(spacing: 12) {
                    Image(nsImage: BrandAssets.notch).font(.largeTitle)
                    Text("A quiet place for your next thought.").font(.headline)
                    Text("Choose a UTF-8 text or Markdown file to start writing.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Choose File…", action: choose)
                        Button("New File…", action: create)
                    }
                    Text("Expand the chevron for file controls, or press ⌘, for Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else if model.preview {
                ScrollView {
                    Text((try? AttributedString(markdown: model.text,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(model.text))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }.disabled(!model.isOpen)
            } else {
                NativeEditor(text: $model.text, selection: model.editorSelection,
                             selectionRevision: model.selectionRevision,
                             selectionChanged: model.rememberEditorSelection,
                             scrollOrigin: model.editorScrollOrigin,
                             scrollChanged: model.rememberEditorScrollOrigin)
                    .disabled(!model.isOpen)
            }
            // Recovery never lives inside a collapsed disclosure.
            if let error = model.error {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    if model.isOpen {
                        HStack {
                            Button("Retry Save") { Task { await model.save() } }
                            Button("Save a Copy…", action: saveCopy)
                            Button("Reload from Disk…", action: reload)
                        }
                    } else {
                        Button("Choose Another File…", action: choose)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.controlsExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.filename).font(.headline).lineLimit(1)
                    if let url = model.url {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(url.path)
                            .accessibilityLabel("File path: \(url.path)")
                            .accessibilityIdentifier("noteFilePath")
                    }
                    Text(model.isOpen
                        ? (model.isDirty ? "Unsaved edits · saves when closed" : "File-backed note")
                        : "No note open")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(model.preview ? "Read-only preview · inline Markdown" : "UTF-8 · ⌘S to save")
                        Spacer()
                        Text("Esc / ⌘↵ to close")
                    }.font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Group {
                            EditorModeButton(isOn: $model.pinned,
                                symbol: model.pinned ? "pin.fill" : "pin",
                                label: "Pin note open",
                                help: model.pinned ? "Unpin: close when pointer leaves" : "Pin note open",
                                identifier: "pinNote")
                            EditorModeButton(isOn: $model.preview,
                                symbol: model.preview ? "pencil" : "eye",
                                label: "Markdown preview",
                                help: model.preview ? "Edit plain-text source" : "Preview Markdown",
                                identifier: "previewMarkdown")
                        }.disabled(!model.isOpen)
                        Spacer()
                        NotchControlButton(symbol: "gearshape", identifier: "openSettings",
                            label: "Open Scribbit settings", help: "Settings (⌘,)",
                            action: showSettings)
                            .frame(width: 28, height: 22)
                    }
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                .accessibilityIdentifier("noteInformation")
            }
            NoteFooter(isExpanded: model.controlsExpanded) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AnimationSpeed.duration(0.16, rate: model.animationSpeed))) {
                    model.controlsExpanded.toggle()
                }
            }
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView("Updating file…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .background(Color(white: 0.035))
    }
}

/// Editing modes are toolbar-style icon buttons, not preference checkboxes.
private struct EditorModeButton: View {
    @Binding var isOn: Bool
    let symbol: String
    let label: String
    let help: String
    let identifier: String

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: symbol)
                .frame(width: 28, height: 24)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(isOn ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    var selection: NSRange?
    var selectionRevision = 0
    var selectionChanged: (NSRange) -> Void = { _ in }
    var scrollOrigin: CGPoint?
    var scrollChanged: (CGPoint) -> Void = { _ in }
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
        coordinator.parent.scrollChanged(scroll.contentView.bounds.origin)
        coordinator.stopObservingHistory()
        editor.isEditable = false
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.delegate = nil
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        private var lastModelText: String?
        private var restoredRevision: Int?
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
            let textChanged = lastModelText.map { !$0.utf8.elementsEqual(value.utf8) } ?? true
            let restore = parent.selection != nil && restoredRevision != parent.selectionRevision
            guard textChanged || restore else { return }
            isSynchronizing = true
            defer { isSynchronizing = false }
            let selection = restore ? parent.selection! : editor.selectedRange()
            if textChanged {
                (editor as? NoteTextView)?.restoreViewport(nil)
                editor.unmarkText()
                editor.string = value
                editor.undoManager?.removeAllActions()
            }
            editor.setSelectedRange(TextSelection.clamped(selection, in: value))
            if restore { editor.scrollRangeToVisible(editor.selectedRange()) }
            if restore { (editor as? NoteTextView)?.restoreViewport(parent.scrollOrigin) }
            restoredRevision = parent.selectionRevision
            lastModelText = value
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            rememberSelection(editor)
        }
        private func rememberSelection(_ editor: NSTextView) {
            guard !isSynchronizing, !editor.hasMarkedText() else { return }
            parent.selectionChanged(editor.selectedRange())
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
            rememberSelection(editor)
        }
    }
}
