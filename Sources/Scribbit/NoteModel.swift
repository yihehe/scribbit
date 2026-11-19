import AppKit
import Combine
import CryptoKit
import ScribbitCore

// Viewport identity keeps only 32 bytes across close, independently of the
// store's bounded hidden snapshot cache. Hashing occurs
// on the existing file worker, never during scrolling or selection movement.
private func sourceFingerprint(_ source: String) -> Data {
    Data(SHA256.hash(data: Data(source.utf8)))
}

/// The serial worker exclusively owns the synchronous session. File coordination
/// and disk I/O never run on the UI thread. Controls freeze during a transaction.
// Safety: only queue.async closures access session; queue is serial and immutable.
private final class SessionWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.stephenhe.Scribbit.files", qos: .userInitiated)
    private let session: NoteSession
    init(session: NoteSession) { self.session = session }
    func perform<T: Sendable>(_ operation: @escaping @Sendable (NoteSession) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation(self.session) })
            }
        }
    }
}

@MainActor
final class NoteModel: ObservableObject {
    @Published var text = ""
    @Published var error: String?
    @Published var filename = "Untitled note"
    @Published var preview = false
    @Published var pinned = false
    @Published var controlsExpanded = false
    @Published var animationSpeed = 1.0
    @Published var hoverDelay = HoverDelay.defaultValue
    @Published private(set) var isUntitled = true
    @Published private(set) var isBusy = false
    /// One concrete asynchronous editor seam. Native operation has no callback.
    /// Browser change notifications are dirty intent, never authoritative bytes.
    var captureEditor: ((_ inspectionOnly: Bool) async throws -> String?)?
    var finishEditor: ((EditorSettlementOutcome, String) -> Void)?
    var invalidateEditor: (() -> Void)?
    @Published private(set) var pendingEditorChanges = false
    func editorDidChange(_ dirty: Bool = true) {
        guard dirty != pendingEditorChanges else { return }
        pendingEditorChanges = dirty
    }
    func prepareEditor(_ operation: () async -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await operation()
    }
    private func captureCurrentEditor() async throws {
        if let source = try await captureEditor?(false) {
            text = source
            pendingEditorChanges = false
        }
    }
    /// Dirty decisions need final browser revision/composition settlement even
    /// if no change notification has arrived. Inspection does not serialize
    /// Markdown, so an unsafe conversion can still be explicitly discarded.
    func settleEditorForDecision() async -> Bool {
        guard !isBusy else { return false }
        guard captureEditor != nil else { return true }
        isBusy = true
        defer { isBusy = false; finishEditor?(.retained, text) }
        do {
            if let unchangedSource = try await captureEditor?(true) {
                text = unchangedSource
                pendingEditorChanges = false
            }
            return true
        }
        catch { self.error = error.localizedDescription; return false }
    }
    func discardRichDraftForSource() {
        guard !isBusy else { return }
        pendingEditorChanges = false
        invalidateEditor?()
    }
    /// A mode change settles the editor, never the file. The file/session baseline
    /// must remain unchanged until an actual save succeeds.
    @discardableResult
    func changeEditorMode(toRich: Bool, importRich: (String, URL?) async -> Bool,
                          activateSource: () -> Void) async -> Bool {
        guard isOpen, !isBusy, !resetInProgress else { return false }
        isBusy = true
        defer { isBusy = false }
        if toRich {
            // The controller commits native composition before taking this gate.
            guard await importRich(text, url) else { return false }
            error = nil
            return true
        }
        do {
            try await captureCurrentEditor()
            editorSelection = TextSelection.clamped(editorSelection, in: text)
            selectionRevision &+= 1
            activateSource()
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            finishEditor?(.retained, text)
            return false
        }
    }
    // Freeze native editing while a confirmed reset awaits login removal.
    @Published var resetInProgress = false
    @Published private(set) var isOpen = false
    @Published private(set) var selectionRevision = 0
    // Only the current file's position, in RAM. Clearing hidden text must not
    // clear this, and caret movement must not invalidate the SwiftUI hierarchy.
    private(set) var editorSelection = NSRange(location: 0, length: 0)
    private(set) var editorScrollOrigin: CGPoint?
    private var closedSourceFingerprint: Data?
    private(set) var url: URL?
    private var baselineText = ""
    private let worker: SessionWorker
    init(session: NoteSession = NoteSession(store: WatchedNoteStore())) { worker = SessionWorker(session: session) }
    var isDirty: Bool { pendingEditorChanges || (isUntitled ? !text.isEmpty : isOpen && !text.utf8.elementsEqual(baselineText.utf8)) }

    /// Untitled text stays RAM-only across hover dismissal; no file worker session exists.
    func openUntitled() {
        guard !isBusy, !isOpen else { return }
        if !isUntitled {
            editorSelection = NSRange(location: 0, length: 0)
            editorScrollOrigin = nil
        }
        isUntitled = true
        url = nil
        filename = "Untitled note"
        isOpen = true
        controlsExpanded = false
        preview = false
        selectionRevision &+= 1
    }
    func discardUntitled() {
        guard isUntitled, !isBusy else { return }
        text = ""
        pendingEditorChanges = false
        invalidateEditor?()
        baselineText = ""
        editorSelection = NSRange(location: 0, length: 0)
        editorScrollOrigin = nil
        selectionRevision &+= 1
    }
    /// Never overwrite an existing destination on behalf of an untitled draft.
    func saveUntitled(to destination: URL) async -> Bool {
        guard isUntitled, !isBusy else { return false }
        isBusy = true
        var outcome = EditorSettlementOutcome.retained
        defer { isBusy = false; finishEditor?(outcome, text) }
        do {
            try await captureCurrentEditor()
            let current = text
            try await worker.perform { session in
                let data = Data(current.utf8)
                guard data.count <= DiskNoteStore.maximumBytes else { throw NoteError.tooLarge }
                try data.write(to: destination, options: .withoutOverwriting)
                // A non-cooperating writer may replace the newly created file.
                // Compare exact bytes before adoption, not BOM-normalized strings.
                try session.open(destination, expectedBytes: data)
            }
            url = destination
            filename = destination.lastPathComponent
            baselineText = current
            isUntitled = false
            isOpen = true
            preview = false
            selectionRevision &+= 1
            error = nil
            outcome = .saved
            return true
        } catch {
            self.error = "Cannot save untitled note. Your draft is still here. Choose a new file path. " + error.localizedDescription
            return false
        }
    }

    func open(_ url: URL) async -> Bool {
        guard !isBusy, !isOpen, !isUntitled || text.isEmpty else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let loaded = try await worker.perform { session in
                try session.open(url)
                return (text: session.text, fingerprint: sourceFingerprint(session.text))
            }
            if self.url != url || closedSourceFingerprint != loaded.fingerprint {
                editorScrollOrigin = nil
            }
            editorSelection = TextSelection.clamped(
                self.url == url ? editorSelection : NSRange(location: 0, length: 0), in: loaded.text)
            selectionRevision &+= 1
            self.url = url
            text = loaded.text
            baselineText = loaded.text
            filename = url.lastPathComponent
            isUntitled = false
            pendingEditorChanges = false
            controlsExpanded = false
            preview = false
            isOpen = true
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    /// Controller must resolve Save/Discard/Cancel and login removal first.
    /// This only clears app-owned in-memory state, never the note on disk.
    func resetDiscardingEdits() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await worker.perform { $0.resetDiscardingEdits() }
            url = nil
            text = ""
            baselineText = ""
            closedSourceFingerprint = nil
            editorSelection = NSRange(location: 0, length: 0)
            editorScrollOrigin = nil
            pendingEditorChanges = false
            invalidateEditor?()
            selectionRevision &+= 1
            filename = "Untitled note"
            isUntitled = true
            isOpen = true
            error = nil
            preview = false
            pinned = false
            controlsExpanded = false
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func rememberEditorSelection(_ selection: NSRange) {
        guard isOpen, !isBusy else { return }
        editorSelection = selection
    }
    func rememberEditorScrollOrigin(_ origin: CGPoint) {
        guard isOpen, !isBusy, origin.x.isFinite, origin.y.isFinite else { return }
        editorScrollOrigin = origin
    }
    func close(keepPresentation: Bool = false) async -> Bool {
        guard !isBusy else { return false }
        guard isOpen else { return true }
        isBusy = true
        var outcome = EditorSettlementOutcome.retained
        var settledSource = text
        defer { isBusy = false; finishEditor?(outcome, settledSource) }
        do {
            try await captureCurrentEditor()
            settledSource = text
            if isUntitled {
                isOpen = false
                outcome = .closed
                if !keepPresentation { clearClosedPresentation() }
                return true
            }
            let current = text
            let fingerprint = try await worker.perform { session in
                session.text = current
                try session.close()
                return sourceFingerprint(current)
            }
            closedSourceFingerprint = fingerprint
            isOpen = false
            if !keepPresentation { clearClosedPresentation() }
            error = nil
            outcome = .closed
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func clearClosedPresentation() {
        guard !isOpen else { return }
        if !isUntitled {
            text = ""
            baselineText = ""
        }
        preview = false
        pinned = false
        controlsExpanded = false
    }
    func save() async {
        guard !isBusy, isOpen, !isUntitled else { return }
        isBusy = true
        var outcome = EditorSettlementOutcome.retained
        defer { isBusy = false; finishEditor?(outcome, text) }
        do {
            try await captureCurrentEditor()
            let current = text
            try await worker.perform { session in session.text = current; try session.save() }
            baselineText = current
            error = nil
            outcome = .saved
        } catch { self.error = error.localizedDescription }
    }
    func reload() async {
        guard !isBusy, isOpen, !isUntitled else { return }
        isBusy = true
        let current = text
        defer { isBusy = false }
        do {
            let loaded = try await worker.perform { session in
                try session.reloadDiscardingEdits()
                return (text: session.text, unchanged: current.utf8.elementsEqual(session.text.utf8))
            }
            if !loaded.unchanged { editorScrollOrigin = nil }
            text = loaded.text
            pendingEditorChanges = false
            invalidateEditor?()
            baselineText = loaded.text
            editorSelection = TextSelection.clamped(editorSelection, in: loaded.text)
            selectionRevision &+= 1
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func createIfMissing(_ destination: URL) async -> Bool {
        guard !isBusy, !isOpen else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await worker.perform { _ in try DiskNoteStore.createIfMissing(destination) }
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func saveCopy(to destination: URL) async {
        guard !isBusy, isOpen, !isUntitled else { return }
        guard destination.resolvingSymlinksInPath() != url else {
            error = "Choose a different path for the copy. The original was not overwritten."
            return
        }
        isBusy = true
        defer { isBusy = false; finishEditor?(.retained, text) }
        do {
            try await captureCurrentEditor()
            let current = text
            try await worker.perform { _ in try Data(current.utf8).write(to: destination, options: .atomic) }
        } catch { self.error = error.localizedDescription }
    }
}
