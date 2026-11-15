import Foundation

/// UI-independent lifecycle. Failed reads/writes never destroy the current buffer.
public final class NoteSession {
    public private(set) var url: URL?
    public private(set) var isOpen = false
    public var text = ""
    private var baseline = Data()
    private let store: NoteStore
    public var isDirty: Bool { isOpen && Data(text.utf8) != baseline }

    public init(store: NoteStore = DiskNoteStore()) { self.store = store }

    /// Call only after the old session has successfully closed.
    public func open(_ url: URL) throws {
        guard !isOpen else { return }
        let bytes = try store.read(url)
        guard let decoded = String(data: bytes, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        self.url = url
        baseline = bytes
        text = decoded
        isOpen = true
    }

    /// Explicit discard action; reads first so a failed reload preserves edits.
    public func reloadDiscardingEdits() throws {
        guard let url, isOpen else { throw NoteError.notOpen }
        let bytes = try store.read(url)
        guard let decoded = String(data: bytes, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        baseline = bytes
        text = decoded
    }

    public func save() throws {
        guard isOpen, let url else { throw NoteError.notOpen }
        // Don't touch externally modified files when we have nothing to save.
        guard isDirty else { return }
        let bytes = Data(text.utf8)
        try store.save(bytes, to: url, replacing: baseline)
        baseline = bytes
    }

    public func close() throws {
        guard isOpen else { return }
        try save()
        isOpen = false
        text = ""
        baseline = Data()
    }
}
