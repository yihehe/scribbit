import Foundation
import Testing
@testable import Scribbit
import ScribbitCore

private final class TestStore: NoteStore {
    var bytes = Data("hello".utf8)
    var failSave = false
    var failRead = false
    func read(_ url: URL) throws -> Data {
        if failRead { throw CocoaError(.fileReadNoPermission) }
        return bytes
    }
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        guard bytes == baseline else { throw NoteError.conflict }
        bytes = data
    }
}

final class NoteModelTests {
    private let url = URL(fileURLWithPath: "/example/note.md")
    @Test @MainActor func testModelOpenSaveCloseAndReopen() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        let opened = await model.open(url)
        expectTrue(opened)
        expectEqual(model.text, "hello")
        expectEqual(model.filename, "note.md")
        model.text = "edited"
        expectTrue(model.isDirty)
        await model.save()
        expectFalse(model.isDirty)
        expectTrue(model.isOpen)
        let closed = await model.close()
        expectTrue(closed)
        store.bytes = Data("external".utf8)
        let reopened = await model.open(url)
        expectTrue(reopened)
        expectEqual(model.text, "external")
        expectFalse(model.isBusy)
    }
    @Test @MainActor func testModelWriteFailureRetainsEditableTextAndError() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        _ = await model.open(url)
        model.text = "keep"
        store.failSave = true
        let closed = await model.close()
        expectFalse(closed)
        expectTrue(model.isOpen)
        expectEqual(model.text, "keep")
        expectNotNil(model.error)
        expectFalse(model.isBusy)
        store.failSave = false
        let retry = await model.close()
        expectTrue(retry)
        expectNil(model.error)
    }
    @Test @MainActor func testModelReloadExplicitlyDiscardsAndResetsPreviewOnOpen() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        _ = await model.open(url)
        model.text = "unsaved"
        store.bytes = Data("disk".utf8)
        await model.reload()
        expectEqual(model.text, "disk")
        expectFalse(model.isDirty)
        model.preview = true
        _ = await model.close()
        _ = await model.open(url)
        expectFalse(model.preview)
    }
    @Test @MainActor func testAlreadyOpenCannotSwitchOrLoseEdits() async {
        let model = NoteModel(session: NoteSession(store: TestStore()))
        _ = await model.open(url)
        model.text = "keep"
        let opened = await model.open(URL(fileURLWithPath: "/other.md"))
        expectFalse(opened)
        expectEqual(model.url, url)
        expectEqual(model.text, "keep")
    }
    @Test @MainActor func testReadFailureAndReloadFailureAreNonDestructive() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        store.failRead = true
        let failedOpen = await model.open(url)
        expectFalse(failedOpen)
        expectFalse(model.isOpen)
        expectNotNil(model.error)
        expectFalse(model.isBusy)
        store.failRead = false
        _ = await model.open(url)
        model.text = "keep edits"
        store.failRead = true
        await model.reload()
        expectEqual(model.text, "keep edits")
        expectTrue(model.isDirty)
        expectTrue(model.isOpen)
        expectNotNil(model.error)
    }
    @Test @MainActor func testManualSaveFailureKeepsDirtyAndCanRetry() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        _ = await model.open(url)
        model.text = "edited"
        store.failSave = true
        await model.save()
        expectNotNil(model.error)
        expectTrue(model.isDirty)
        expectTrue(model.isOpen)
        store.failSave = false
        await model.save()
        expectNil(model.error)
        expectFalse(model.isDirty)
    }
    @Test @MainActor func testCopyExportsBufferWithoutResolvingOriginalSession() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/model-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = NoteModel(session: NoteSession(store: TestStore()))
        _ = await model.open(url)
        model.text = "my unsaved copy"
        let copy = directory.appendingPathComponent("copy.md")
        await model.saveCopy(to: copy)
        expectEqual(try String(contentsOf: copy, encoding: .utf8), "my unsaved copy")
        expectTrue(model.isOpen)
        expectTrue(model.isDirty)
        expectEqual(model.url, url)
        await model.saveCopy(to: directory.appendingPathComponent("missing/copy.md"))
        expectNotNil(model.error)
        expectEqual(model.text, "my unsaved copy")
    }
    @Test @MainActor func testCreateNewOrExistingAndSurfaceCreationErrors() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/model-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = NoteModel()
        let newURL = directory.appendingPathComponent("new.md")
        let created = await model.createIfMissing(newURL)
        expectTrue(created)
        expectEqual(try Data(contentsOf: newURL), Data())
        try Data("existing".utf8).write(to: newURL)
        let existing = await model.createIfMissing(newURL)
        expectTrue(existing)
        expectEqual(try String(contentsOf: newURL, encoding: .utf8), "existing")
        let failed = await model.createIfMissing(directory.appendingPathComponent("missing/new.md"))
        expectFalse(failed)
        expectNotNil(model.error)
        expectFalse(model.isBusy)
    }
    @Test @MainActor func testCopyCannotBypassOriginalFileConflictProtection() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/model-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.md")
        try Data("original".utf8).write(to: original)
        let model = NoteModel()
        _ = await model.open(original)
        model.text = "do not force overwrite"
        await model.saveCopy(to: original)
        expectNotNil(model.error)
        expectEqual(try String(contentsOf: original, encoding: .utf8), "original")
        expectTrue(model.isDirty)
        let alias = directory.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        await model.saveCopy(to: alias)
        expectEqual(try String(contentsOf: original, encoding: .utf8), "original")
    }
    @Test @MainActor func testIsolatedSettingsHaveNoPersistenceDependency() {
        let settings = AppSettings(isolated: true)
        expectNil(settings.bookmark)
        expectFalse(settings.indicator)
        expectFalse(settings.didOfferLogin)
        settings.bookmark = Data([1, 2, 3])
        settings.indicator = true
        settings.didOfferLogin = true
        expectEqual(settings.bookmark, Data([1, 2, 3]))
        expectTrue(settings.indicator)
        expectTrue(settings.didOfferLogin)
        let fresh = AppSettings(isolated: true)
        expectNil(fresh.bookmark)
        expectFalse(fresh.didOfferLogin)
    }
    @Test @MainActor func testAnimationSpeedPersistsOnlyInSelectedSettingsStoreAndClamps() {
        let settings = AppSettings(isolated: true)
        #expect(settings.animationSpeed == 1)
        settings.animationSpeed = 1.75
        #expect(settings.animationSpeed == 1.75)
        settings.animationSpeed = .nan
        #expect(settings.animationSpeed == 1)
        settings.animationSpeed = 100
        #expect(settings.animationSpeed == 2)
        settings.animationSpeed = -100
        #expect(settings.animationSpeed == 0.5)
        #expect(AppSettings(isolated: true).animationSpeed == 1)
    }
    @Test @MainActor func testControlsStartCollapsedOnEveryOpenWithoutResettingSpeed() async {
        let model = NoteModel(session: NoteSession(store: TestStore()))
        #expect(!model.controlsExpanded)
        _ = await model.open(url)
        model.text = "Keep this text"
        model.controlsExpanded = true
        model.controlsExpanded = false
        #expect(model.text == "Keep this text")
        model.animationSpeed = 1.5
        _ = await model.close()
        _ = await model.open(url)
        #expect(!model.controlsExpanded)
        #expect(model.animationSpeed == 1.5)
        #expect(model.text == "Keep this text")
    }
    @Test @MainActor func testOutgoingPresentationSurvivesSaveUntilCollapseFinishes() async {
        let store = TestStore()
        let model = NoteModel(session: NoteSession(store: store))
        _ = await model.open(url)
        model.text = "Keep visible during collapse"
        model.pinned = true
        let closed = await model.close(keepPresentation: true)
        expectTrue(closed)
        expectFalse(model.isOpen)
        expectEqual(model.text, "Keep visible during collapse")
        expectEqual(store.bytes, Data("Keep visible during collapse".utf8))
        model.clearClosedPresentation()
        expectEqual(model.text, "")
        expectFalse(model.pinned)
    }
    @Test @MainActor func testDiskWorkDoesNotBlockMainActorAndSerializesActions() async {
        final class SlowStore: NoteStore {
            let release = DispatchSemaphore(value: 0)
            let started: AsyncStream<Void>
            private let continuation: AsyncStream<Void>.Continuation
            init() {
                let pair = AsyncStream<Void>.makeStream()
                started = pair.stream
                continuation = pair.continuation
            }
            func read(_ url: URL) throws -> Data {
                expectFalse(Thread.isMainThread)
                continuation.yield(())
                release.wait()
                return Data("slow".utf8)
            }
            func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
                expectFalse(Thread.isMainThread)
            }
        }
        let store = SlowStore()
        let model = NoteModel(session: NoteSession(store: store))
        let operation = Task { await model.open(url) }
        var started = store.started.makeAsyncIterator()
        _ = await started.next()
        expectTrue(model.isBusy)
        let duplicate = await model.open(url)
        expectFalse(duplicate)
        let prematureClose = await model.close()
        expectFalse(prematureClose)
        await model.save()
        await model.reload()
        let creationWhileBusy = await model.createIfMissing(url)
        expectFalse(creationWhileBusy)
        await model.saveCopy(to: url)
        store.release.signal()
        let result = await operation.value
        expectTrue(result)
        model.text = "changed"
        _ = await model.close()
    }
}
