import Foundation

/// UI-independent lifecycle. Failed reads/writes never destroy the current buffer.
public final class NoteSession {
    public private(set) var url: URL?
    public private(set) var isOpen = false
    public var text = ""
    private var baseline = Data()
    private var decodedBaseline = ""
    private let store: NoteStore
    public var isDirty: Bool { isOpen && !text.utf8.elementsEqual(decodedBaseline.utf8) }

    public init(store: NoteStore = DiskNoteStore()) { self.store = store }

    /// Call only after the old session has successfully closed.
    /// expectedBytes is used only when adopting a newly created draft file.
    /// Validate raw bytes before decoding (UTF-8 decoding consumes an initial BOM).
    public func open(_ url: URL, expectedBytes: Data? = nil) throws {
        guard !isOpen else { return }
        let bytes = try store.read(url)
        if let expectedBytes, bytes != expectedBytes { throw NoteError.conflict }
        guard let decoded = String(data: bytes, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        self.url = url
        baseline = bytes
        text = decoded
        decodedBaseline = decoded
        isOpen = true
    }

    /// Explicit discard action; reads first so a failed reload preserves edits.
    public func reloadDiscardingEdits() throws {
        guard let url, isOpen else { throw NoteError.notOpen }
        store.invalidateCache()
        let bytes = try store.read(url)
        guard let decoded = String(data: bytes, encoding: .utf8) else { throw NoteError.invalidUTF8 }
        baseline = bytes
        text = decoded
        decodedBaseline = decoded
    }

    public func save() throws {
        guard isOpen, let url else { throw NoteError.notOpen }
        // Don't touch externally modified files when we have nothing to save.
        guard isDirty else { return }
        var bytes = Data(text.utf8)
        // Foundation's UTF-8 decoding consumes an encoding BOM. Keep the
        // original byte baseline for conflicts and preserve its BOM on edits.
        let bom = Data([0xEF, 0xBB, 0xBF])
        if baseline.starts(with: bom), !bytes.starts(with: bom) { bytes = bom + bytes }
        // A newly adopted BOM draft may retain the marker in its UI string,
        // while Foundation decoded the session baseline without it. Equal
        // serialized bytes are a clean no-op, not an atomic rewrite.
        if bytes == baseline {
            decodedBaseline = text
            return
        }
        try store.save(bytes, to: url, replacing: baseline)
        baseline = bytes
        decodedBaseline = text
    }

    public func close() throws {
        guard isOpen else { return }
        try save()
        isOpen = false
        text = ""
        baseline = Data()
        decodedBaseline = ""
    }
    /// Explicitly confirmed app reset only. No reads, writes or file deletion.
    public func resetDiscardingEdits() {
        store.invalidateCache()
        url = nil
        isOpen = false
        text = ""
        baseline = Data()
        decodedBaseline = ""
    }

}
