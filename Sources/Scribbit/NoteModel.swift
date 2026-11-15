import AppKit
import Combine
import ScribbitCore

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
    @Published private(set) var isBusy = false
    @Published private(set) var isOpen = false
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
                return session.text
            }
            self.url = url
            text = loaded
            baselineText = loaded
            filename = url.lastPathComponent
            controlsExpanded = false
            preview = false
            isOpen = true
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func close(keepPresentation: Bool = false) async -> Bool {
        guard !isBusy else { return false }
        guard isOpen else { return true }
        isBusy = true
        let current = text
        defer { isBusy = false }
        do {
            try await worker.perform { session in session.text = current; try session.close() }
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
        defer { isBusy = false }
        do {
            let loaded = try await worker.perform { session in
                try session.reloadDiscardingEdits()
                return session.text
            }
            text = loaded
            baselineText = loaded
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
