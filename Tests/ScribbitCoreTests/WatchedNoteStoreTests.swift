import Foundation
import Testing
@testable import ScribbitCore

final class WatchedNoteStoreTests {
    private final class CountingStore: NoteStore {
        let disk = DiskNoteStore()
        var reads = 0
        var saves = 0
        func read(_ url: URL) throws -> Data { reads += 1; return try disk.read(url) }
        func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
            saves += 1
            try disk.save(data, to: url, replacing: baseline)
        }
    }
    private let directory: URL
    private var url: URL { directory.appendingPathComponent("note.md") }
    init() throws {
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test func unchangedReopenUsesOneSnapshotButSessionStillClears() throws {
        try Data("hello".utf8).write(to: url)
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        let session = NoteSession(store: store)
        try session.open(url); try session.close()
        expectEqual(session.text, "")
        try session.open(url)
        expectEqual(session.text, "hello")
        expectEqual(disk.reads, 1)
        try session.reloadDiscardingEdits()
        expectEqual(disk.reads, 2)
    }

    @Test func replacementDeletionRecreationAndSameLengthEditAreNotStale() throws {
        let store = WatchedNoteStore()
        try Data("first".utf8).write(to: url)
        expectEqual(try store.read(url), Data("first".utf8))
        try Data("other".utf8).write(to: url)
        expectEqual(try store.read(url), Data("other".utf8))
        try Data("third".utf8).write(to: url, options: .atomic)
        expectEqual(try store.read(url), Data("third".utf8))
        try FileManager.default.removeItem(at: url)
        expectThrowsError(try store.read(url))
        try Data("again".utf8).write(to: url)
        expectEqual(try store.read(url), Data("again".utf8))
    }

    @Test func watcherInvalidatesOnDirectoryEventWithoutTargetMetadataChange() throws {
        try Data("hello".utf8).write(to: url)
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        _ = try store.read(url)
        try Data().write(to: directory.appendingPathComponent("sibling"))
        let deadline = Date().addingTimeInterval(3)
        while disk.reads == 1, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
            _ = try store.read(url)
        }
        expectTrue(disk.reads > 1)
    }

    @Test func saveNeverTrustsCacheForConflictAndFailedSavePreservesExternalBytes() throws {
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        let initial = Data("first".utf8)
        try initial.write(to: url)
        _ = try store.read(url)
        try Data("other".utf8).write(to: url)
        expectThrowsError(try store.save(Data("mine".utf8), to: url, replacing: initial)) {
            expectEqual($0 as? NoteError, .conflict)
        }
        expectEqual(disk.saves, 1)
        expectEqual(try store.read(url), Data("other".utf8))
    }

    @Test func successfulSaveInvalidatesAndExternalChangesNeverReplaceVisibleEdits() throws {
        try Data("first".utf8).write(to: url)
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        let session = NoteSession(store: store)
        try session.open(url)
        session.text = "saved"
        try session.save()
        expectEqual(try store.read(url), Data("saved".utf8))
        expectEqual(disk.reads, 2)
        session.text = "unsaved"
        try Data("external".utf8).write(to: url, options: .atomic)
        // Reading the new snapshot does not publish into the editing session.
        expectEqual(try store.read(url), Data("external".utf8))
        try session.open(url)
        expectEqual(session.text, "unsaved")
        expectThrowsError(try session.close()) {
            expectEqual($0 as? NoteError, .conflict)
        }
        expectTrue(session.isOpen)
        expectEqual(session.text, "unsaved")
    }

    @Test func resetDropsHiddenSnapshotWithoutReadingWritingOrDeletingNote() throws {
        let original = Data("keep this note".utf8)
        try original.write(to: url)
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        let session = NoteSession(store: store)
        try session.open(url)
        try session.close()
        expectEqual(disk.reads, 1)
        session.resetDiscardingEdits()
        session.resetDiscardingEdits()
        expectEqual(disk.reads, 1)
        expectEqual(disk.saves, 0)
        expectEqual(try Data(contentsOf: url), original)
        expectEqual(session.url, nil)
        expectEqual(session.text, "")
        // The unchanged file cannot reuse the pre-reset hidden snapshot.
        try session.open(url)
        expectEqual(disk.reads, 2)
    }

    @Test func switchingFilesAndExplicitInvalidationDropPreviousSnapshot() throws {
        let other = directory.appendingPathComponent("other.md")
        try Data("one".utf8).write(to: url)
        try Data("two".utf8).write(to: other)
        let disk = CountingStore()
        let store = WatchedNoteStore(store: disk)
        _ = try store.read(url); _ = try store.read(other); _ = try store.read(url)
        expectEqual(disk.reads, 3)
        store.invalidateCache()
        _ = try store.read(url)
        expectEqual(disk.reads, 4)
    }
}
