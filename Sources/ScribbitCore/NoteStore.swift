import Foundation

public enum NoteError: LocalizedError, Equatable {
    case invalidUTF8, tooLarge, conflict, notOpen, unsupportedFile
    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "This file is not UTF-8 text. Choose a UTF-8 .txt or .md file."
        case .tooLarge: return "This note exceeds the 2 MiB limit. Choose a smaller file."
        case .conflict: return "The file changed or was removed on disk. Your edits are still here. Save a copy, or reload to discard your edits."
        case .notOpen: return "No note is open."
        case .unsupportedFile: return "Choose a regular text file, not a directory or special file."
        }
    }
}

public protocol NoteStore {
    func read(_ url: URL) throws -> Data
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws
}

/// Coordinates with participating macOS editors and checks bytes before atomic replacement.
/// Non-cooperating writers can still race; this is not a distributed file lock.
public final class DiskNoteStore: NoteStore {
    public static let maximumBytes = 2 * 1024 * 1024
    public init() {}

    /// An empty new file needs no atomic replacement. Foundation explicitly
    /// forbids combining atomic and withoutOverwriting. Never truncate a file
    /// selected through the Create dialog, even after system replace approval.
    public static func createIfMissing(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try Data().write(to: url, options: .withoutOverwriting)
    }

    private func readUncoordinated(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw NoteError.unsupportedFile }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= Self.maximumBytes else { throw NoteError.tooLarge }
        // Bounded read also handles a file growing between stat and read.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw NoteError.tooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw NoteError.invalidUTF8 }
        return data
    }

    public func read(_ url: URL) throws -> Data {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try self.readUncoordinated(coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    public func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        guard data.count <= Self.maximumBytes else { throw NoteError.tooLarge }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            result = Result {
                let current: Data
                do { current = try self.readUncoordinated(coordinated) }
                catch { throw NoteError.conflict }
                guard current == baseline else { throw NoteError.conflict }
                try data.write(to: coordinated, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }
}
