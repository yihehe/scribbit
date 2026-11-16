import Foundation
import Testing
@testable import ScribbitCore

final class DiskNoteStoreTests {
    private var directory: URL!
    private var url: URL { directory.appendingPathComponent("note.md") }
    private let store = DiskNoteStore()
    init() throws {
        // Keep test fixtures in the project rather than system-wide temp storage.
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    @Test func testRoundTripUnicodeAndLineEndings() throws {
        let initial = Data("# Notes\r\n\r\nこんにちは 📝\r\n".utf8)
        try initial.write(to: url)
        expectEqual(try store.read(url), initial)
        let next = Data("# Updated\n**bold**\n".utf8)
        try store.save(next, to: url, replacing: initial)
        expectEqual(try Data(contentsOf: url), next)
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["note.md"])
    }
    @Test func testEmptyFileIsValid() throws {
        try Data().write(to: url)
        expectEqual(try store.read(url), Data())
        try store.save(Data("hello".utf8), to: url, replacing: Data())
        expectEqual(try store.read(url), Data("hello".utf8))
    }
    @Test func testExternalAtomicReplacementConflicts() throws {
        let initial = Data("before".utf8)
        try initial.write(to: url)
        try Data("elsewhere".utf8).write(to: url, options: .atomic)
        expectThrowsError(try store.save(Data("mine".utf8), to: url, replacing: initial)) {
            expectEqual($0 as? NoteError, .conflict)
        }
        expectEqual(try store.read(url), Data("elsewhere".utf8))
    }
    @Test func testDeletedFileIsNotSilentlyRecreated() throws {
        try Data("before".utf8).write(to: url)
        try FileManager.default.removeItem(at: url)
        expectThrowsError(try store.save(Data("mine".utf8), to: url, replacing: Data("before".utf8)))
        expectFalse(FileManager.default.fileExists(atPath: url.path))
    }
    @Test func testInvalidUTF8RejectedWithoutChanges() throws {
        let binary = Data([0xff, 0xfe, 0x00])
        try binary.write(to: url)
        expectThrowsError(try store.read(url)) { expectEqual($0 as? NoteError, .invalidUTF8) }
        expectEqual(try Data(contentsOf: url), binary)
    }
    @Test func testReadLimitAndExactBoundary() throws {
        let boundary = Data(repeating: 0x61, count: DiskNoteStore.maximumBytes)
        try boundary.write(to: url)
        expectEqual(try store.read(url).count, boundary.count)
        try (boundary + Data([0x61])).write(to: url)
        expectThrowsError(try store.read(url)) { expectEqual($0 as? NoteError, .tooLarge) }
    }
    @Test func testSaveAt64MiBBoundary() throws {
        expectEqual(DiskNoteStore.maximumBytes, 64 * 1024 * 1024)
        try Data().write(to: url)
        let boundary = Data(repeating: 0x61, count: DiskNoteStore.maximumBytes)
        try store.save(boundary, to: url, replacing: Data())
        expectEqual(try store.read(url), boundary)
    }
    @Test func testOversizedSaveDoesNotTouchOriginal() throws {
        try Data("before".utf8).write(to: url)
        expectThrowsError(try store.save(Data(repeating: 0x61, count: DiskNoteStore.maximumBytes + 1),
                                          to: url, replacing: Data("before".utf8))) {
            expectEqual($0 as? NoteError, .tooLarge)
        }
        expectEqual(try store.read(url), Data("before".utf8))
    }
    @Test func testDirectoryAndMissingFileAreRejected() throws {
        expectThrowsError(try store.read(directory)) { expectEqual($0 as? NoteError, .unsupportedFile) }
        expectThrowsError(try store.read(url))
    }
    @Test func testSameLengthExternalEditStillConflicts() throws {
        try Data("aaaa".utf8).write(to: url)
        let baseline = try store.read(url)
        try Data("bbbb".utf8).write(to: url)
        expectThrowsError(try store.save(Data("cccc".utf8), to: url, replacing: baseline))
        expectEqual(try store.read(url), Data("bbbb".utf8))
    }
    @Test func testSessionRefreshesActualDiskAfterClose() throws {
        try Data("one".utf8).write(to: url)
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "two"
        try session.close()
        try Data("three".utf8).write(to: url, options: .atomic)
        try session.open(url)
        expectEqual(session.text, "three")
    }
    @Test func testFileReplacedByDirectoryFailureRetainsBuffer() throws {
        try Data("before".utf8).write(to: url)
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "after"
        // Replace file with a directory to induce a deterministic write failure,
        // independent of whether the test process has elevated permissions.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        expectThrowsError(try session.close())
        expectTrue(session.isOpen)
        expectEqual(session.text, "after")
    }
    @Test func testCreateWithoutOverwritingCanCreateButNeverTruncates() throws {
        try DiskNoteStore.createIfMissing(url)
        expectEqual(try store.read(url), Data())
        try Data("existing".utf8).write(to: url)
        try DiskNoteStore.createIfMissing(url)
        expectEqual(try store.read(url), Data("existing".utf8))
    }
    @Test func testSymlinkIsNotReplacedByCoreStore() throws {
        try Data("original".utf8).write(to: url)
        let link = directory.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        expectThrowsError(try store.read(link)) { expectEqual($0 as? NoteError, .unsupportedFile) }
        // App resolves selection before opening, preserving the symlink itself.
        let session = NoteSession(store: store)
        try session.open(link.resolvingSymlinksInPath())
        session.text = "updated"
        try session.close()
        expectEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), url.path)
        expectEqual(try String(contentsOf: link, encoding: .utf8), "updated")
    }

}
