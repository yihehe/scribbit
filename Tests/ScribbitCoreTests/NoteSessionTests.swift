import Foundation
import Testing
@testable import ScribbitCore

private enum TestFailure: Error { case read, write }
private final class MemoryStore: NoteStore {
    var bytes = Data("original".utf8)
    var reads = 0
    var writes = 0
    var failRead = false
    var failWrite = false
    func read(_ url: URL) throws -> Data {
        reads += 1
        if failRead { throw TestFailure.read }
        return bytes
    }
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        writes += 1
        if failWrite { throw TestFailure.write }
        guard baseline == bytes else { throw NoteError.conflict }
        bytes = data
    }
}

final class NoteSessionTests {
    private let url = URL(fileURLWithPath: "/example/note.md")
    @Test func utf8BOMCleanClosePreservesOriginalBytesAndEditsKeepEncodingMarker() throws {
        let store = MemoryStore()
        let original = Data("\u{FEFF}Original\r\n".utf8)
        store.bytes = original
        let session = NoteSession(store: store)
        try session.open(url)
        #expect(!session.isDirty)
        try session.close()
        #expect(store.writes == 0 && store.bytes == original)
        try session.open(url)
        session.text = "Edited\r\n"
        try session.save()
        #expect(store.bytes == Data("\u{FEFF}Edited\r\n".utf8))
        #expect(!session.isDirty)
        session.text = "Pending"
        store.bytes = Data("Edited\r\n".utf8) // Same text, different exact bytes.
        #expect(throws: NoteError.conflict) { try session.save() }
        #expect(session.text == "Pending" && session.isDirty)
    }
    @Test func confirmedResetDiscardsOnlyMemoryWithoutDiskIO() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "unsaved text"
        store.failRead = true
        store.failWrite = true
        session.resetDiscardingEdits()
        #expect(!session.isOpen && !session.isDirty && session.url == nil && session.text.isEmpty)
        #expect(store.reads == 1 && store.writes == 0 && store.bytes == Data("original".utf8))
        session.resetDiscardingEdits()
        #expect(store.reads == 1 && store.writes == 0)
    }
    @Test func testEveryClosedToOpenTransitionReadsDisk() throws {
        let store = MemoryStore()
        let subject = NoteSession(store: store)
        try subject.open(url)
        expectEqual(subject.text, "original")
        try subject.close()
        store.bytes = Data("external edit".utf8)
        try subject.open(url)
        expectEqual(subject.text, "external edit")
        expectEqual(store.reads, 2)
    }
    @Test func testOpenWhileEditingDoesNotReloadOrChangeFile() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "unsaved"
        try session.open(URL(fileURLWithPath: "/other.md"))
        expectEqual(session.text, "unsaved")
        expectEqual(session.url, url)
        expectEqual(store.reads, 1)
    }
    @Test func testCloseSavesEditsAndClearsDirtyFlag() throws {
        let store = MemoryStore()
        let subject = NoteSession(store: store)
        try subject.open(url)
        subject.text = "edited 📝\n"
        expectTrue(subject.isDirty)
        try subject.close()
        expectFalse(subject.isOpen)
        expectEqual(subject.text, "")
        expectFalse(subject.isDirty)
        expectEqual(String(data: store.bytes, encoding: .utf8), "edited 📝\n")
        expectEqual(store.writes, 1)
    }
    @Test func testFailedClosePreservesOpenBufferAndRetryWorks() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "precious edits"
        store.failWrite = true
        expectThrowsError(try session.close())
        expectTrue(session.isOpen)
        expectTrue(session.isDirty)
        expectEqual(session.text, "precious edits")
        store.failWrite = false
        try session.close()
        expectEqual(store.bytes, Data("precious edits".utf8))
    }
    @Test func testConflictNeverOverwritesExternalEdit() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "my edit"
        store.bytes = Data("their edit".utf8)
        expectThrowsError(try session.close()) { expectEqual($0 as? NoteError, .conflict) }
        expectTrue(session.isOpen)
        expectEqual(session.text, "my edit")
        expectEqual(store.bytes, Data("their edit".utf8))
    }
    @Test func testCleanCloseDoesNotWriteOrOverwriteExternalChanges() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        store.bytes = Data("changed elsewhere".utf8)
        try session.close()
        expectEqual(store.writes, 0)
        expectEqual(store.bytes, Data("changed elsewhere".utf8))
    }
    @Test func testManualSaveUpdatesBaselineForNextSave() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "one"
        try session.save()
        expectFalse(session.isDirty)
        expectTrue(session.isOpen)
        session.text = "two"
        try session.close()
        expectEqual(store.bytes, Data("two".utf8))
    }
    @Test func testFailedOpenDoesNotExposeEditableEmptyFile() {
        let store = MemoryStore()
        store.failRead = true
        let session = NoteSession(store: store)
        expectThrowsError(try session.open(url))
        expectFalse(session.isOpen)
        expectNil(session.url)
    }
    @Test func testInvalidUTF8FailsEvenForAlternateStore() {
        let store = MemoryStore()
        store.bytes = Data([0xFF, 0xFE])
        let session = NoteSession(store: store)
        expectThrowsError(try session.open(url)) { expectEqual($0 as? NoteError, .invalidUTF8) }
        expectFalse(session.isOpen)
    }
    @Test func testReloadDiscardsEditsOnlyAfterSuccessfulRead() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "keep me"
        store.failRead = true
        expectThrowsError(try session.reloadDiscardingEdits())
        expectEqual(session.text, "keep me")
        expectTrue(session.isDirty)
        store.failRead = false
        store.bytes = Data("new baseline".utf8)
        try session.reloadDiscardingEdits()
        expectEqual(session.text, "new baseline")
        expectFalse(session.isDirty)
    }
    @Test func testInvalidReloadPreservesBuffer() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "keep me"
        store.bytes = Data([0xff])
        expectThrowsError(try session.reloadDiscardingEdits())
        expectEqual(session.text, "keep me")
    }
    @Test func testNoOpCloseAndSaveWithoutOpening() throws {
        let store = MemoryStore()
        let session = NoteSession(store: store)
        try session.close()
        expectThrowsError(try session.save()) { expectEqual($0 as? NoteError, .notOpen) }
        expectThrowsError(try session.reloadDiscardingEdits())
        expectEqual(store.reads, 0)
        expectEqual(store.writes, 0)
    }
    @Test func testEditingBackToOriginalIsClean() throws {
        let session = NoteSession(store: MemoryStore())
        try session.open(url)
        session.text = "different"
        session.text = "original"
        expectFalse(session.isDirty)
    }
}
