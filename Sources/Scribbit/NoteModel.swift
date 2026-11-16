import AppKit
import Combine
import CryptoKit
import ScribbitCore

// Keep only 32 bytes across close, not the hidden note's source. Hashing occurs
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
    @Published var filename = "Choose a note"
    @Published var preview = false
    @Published var pinned = false
    @Published var controlsExpanded = false
    @Published var animationSpeed = 1.0
    @Published var hoverDelay = HoverDelay.defaultValue
    @Published private(set) var isBusy = false
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
    init(session: NoteSession = NoteSession()) { worker = SessionWorker(session: session) }
    var isDirty: Bool { isOpen && text != baselineText }

    func open(_ url: URL) async -> Bool {
        guard !isBusy, !isOpen else { return false }
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
            controlsExpanded = false
            preview = false
            isOpen = true
            error = nil
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
        let current = text
        defer { isBusy = false }
        do {
            let fingerprint = try await worker.perform { session in
                session.text = current
                try session.close()
                return sourceFingerprint(current)
            }
            closedSourceFingerprint = fingerprint
            isOpen = false
            if !keepPresentation { clearClosedPresentation() }
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func clearClosedPresentation() {
        guard !isOpen else { return }
        text = ""
        baselineText = ""
        preview = false
        pinned = false
        controlsExpanded = false
    }
    func save() async {
        guard !isBusy, isOpen else { return }
        isBusy = true
        let current = text
        defer { isBusy = false }
        do {
            try await worker.perform { session in session.text = current; try session.save() }
            baselineText = current
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func reload() async {
        guard !isBusy, isOpen else { return }
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
        guard !isBusy, isOpen else { return }
        guard destination.resolvingSymlinksInPath() != url else {
            error = "Choose a different path for the copy. The original was not overwritten."
            return
        }
        isBusy = true
        let current = text
        defer { isBusy = false }
        do {
            try await worker.perform { _ in try Data(current.utf8).write(to: destination, options: .atomic) }
        } catch { self.error = error.localizedDescription }
    }
}
