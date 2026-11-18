import Foundation
import Combine
import Testing
import ScribbitCore
@testable import Scribbit

private final class RichSettlementStore: NoteStore {
    var bytes = Data("Original\r\n".utf8)
    var reads = 0
    var writes = 0
    var failRead = false
    var failSave = false
    func read(_ url: URL) throws -> Data {
        reads += 1
        if failRead { throw CocoaError(.fileReadNoPermission) }
        return bytes
    }
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        guard bytes == baseline else { throw NoteError.conflict }
        writes += 1
        bytes = data
    }
}

@MainActor
struct RichEditorSettlementTests {
    private let url = URL(fileURLWithPath: "/disposable/note.md")
    @Test func repeatedBrowserDirtyIntentDoesNotPublishEveryKeystroke() {
        let model = NoteModel(session: NoteSession(store: RichSettlementStore()))
        var updates = 0
        let subscription = model.objectWillChange.sink { updates += 1 }
        model.editorDidChange()
        model.editorDidChange()
        model.editorDidChange()
        #expect(updates == 1)
        model.editorDidChange(false)
        #expect(updates == 2)
        subscription.cancel()
    }

    @Test func saveUsesLatestAcknowledgedSourceAndCleanCloseDoesNotRewrite() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.captureEditor = { inspection in
            #expect(!inspection)
            return "Latest acknowledged source\r\n"
        }
        model.editorDidChange()
        #expect(model.isDirty)
        await model.save()
        #expect(store.bytes == Data("Latest acknowledged source\r\n".utf8))
        #expect(store.writes == 1 && !model.isDirty)
        #expect(await model.close())
        #expect(store.writes == 1)
    }

    @Test func originalCRLFAndUnicodeBytesSurviveAReadOnlyRoundtrip() async {
        let store = RichSettlementStore()
        store.bytes = Data("\u{FEFF}# Café 🐸\r\n\r\n- item\r\n".utf8)
        let original = store.bytes
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.captureEditor = { _ in String(data: original, encoding: .utf8)! }
        #expect(await model.close())
        #expect(store.writes == 0)
        #expect(store.bytes == original)
    }

    @Test func unchangedLiteralPunctuationSnapshotClosesAndSwitchesWithoutSerializingOrWriting() async throws {
        let store = RichSettlementStore()
        store.bytes = Data("\u{FEFF}A * literal\r\n\r\n".utf8)
        let original = store.bytes
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        let originalSource = model.text
        let doc: [String: Any] = ["type": "doc", "content": [
            ["type": "paragraph", "content": [["type": "text", "text": "A * literal"]]],
            ["type": "paragraph"]
        ]]
        let baseline = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys, .withoutEscapingSlashes])
        model.captureEditor = { _ in
            try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: baseline,
                originalSource: originalSource, serializedSource: nil,
                sourceHasBOM: true, sourceUsesCRLF: true).source
        }
        // Dirty notifications/revisions are hints, not proof of source changes.
        model.editorDidChange()
        #expect(await model.close())
        #expect(store.writes == 0 && store.bytes == original)
        #expect(await model.open(URL(fileURLWithPath: "/disposable/next.md")))
        #expect(model.url?.lastPathComponent == "next.md")
        #expect(store.writes == 0 && store.bytes == original)
    }

    @Test func unsafeExportOrTimeoutCannotHideOrWriteAFile() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        let original = model.text
        var outcome: EditorSettlementOutcome?
        model.captureEditor = { _ in throw RichMarkdownPolicy.failure("Unsafe Markdown or flush timeout.") }
        model.finishEditor = { result, _ in outcome = result }
        model.editorDidChange()
        #expect(await !model.close(keepPresentation: true))
        #expect(model.isOpen && model.isDirty && !model.isBusy)
        #expect(model.text == original && model.error != nil)
        #expect(store.writes == 0 && outcome == .retained)
    }

    @Test func dirtyInspectionDoesNotRequireLossySerializationAndExplicitDiscardCanProceed() async {
        let model = NoteModel(session: NoteSession(store: RichSettlementStore()))
        model.openUntitled()
        model.captureEditor = { inspection in
            if inspection { model.editorDidChange(); return nil }
            throw RichMarkdownPolicy.failure("Cannot safely export this paragraph.")
        }
        #expect(await model.settleEditorForDecision())
        #expect(model.isDirty && model.text.isEmpty)
        #expect(await !model.close())
        var invalidations = 0
        model.invalidateEditor = { invalidations += 1 }
        model.discardUntitled()
        #expect(!model.isDirty && model.text.isEmpty && invalidations == 1)
    }

    @Test func inspectionCanRestoreOriginalBytesAfterUndoWithoutSerializing() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.text = "A previously acknowledged but failed save"
        model.editorDidChange()
        model.captureEditor = { inspection in
            #expect(inspection)
            return "Original\r\n" // Committed tree equality, not serializer output.
        }
        #expect(await model.settleEditorForDecision())
        #expect(!model.isDirty && model.text == "Original\r\n" && store.writes == 0)
    }

    @Test func untitledCloseCapturesLatestSourceButDoesNotWrite() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        model.openUntitled()
        model.captureEditor = { _ in "- [ ] RAM-only task" }
        #expect(await model.close())
        #expect(model.text == "- [ ] RAM-only task" && model.isUntitled && !model.isOpen)
        #expect(store.writes == 0 && store.reads == 0)
    }

    @Test func reentryCannotSaveWhileAnotherSnapshotIsInFlight() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        var resume: CheckedContinuation<String?, Never>?
        model.captureEditor = { _ in await withCheckedContinuation { resume = $0 } }
        let save = Task { await model.save() }
        while resume == nil { await Task.yield() }
        #expect(model.isBusy)
        #expect(await !model.close())
        await model.save()
        #expect(store.writes == 0)
        resume?.resume(returning: "Serialized once")
        await save.value
        #expect(store.writes == 1 && !model.isBusy)
    }

    @Test func failedReloadDoesNotDiscardBrowserIntentButResetInvalidatesIt() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        var invalidations = 0
        model.invalidateEditor = { invalidations += 1 }
        model.editorDidChange()
        store.failRead = true
        await model.reload()
        #expect(model.pendingEditorChanges && invalidations == 0)
        #expect(await model.resetDiscardingEdits())
        #expect(!model.pendingEditorChanges && model.isUntitled && invalidations == 1)
        #expect(store.writes == 0)
    }

    @Test func saveFailureRetainsCurrentAcknowledgedSourceAndDirtyState() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        store.failSave = true
        model.captureEditor = { _ in "Do not lose this rich edit" }
        model.editorDidChange()
        await model.save()
        #expect(model.text == "Do not lose this rich edit" && model.isDirty && model.isOpen)
        #expect(store.bytes == Data("Original\r\n".utf8) && model.error != nil)
    }

    @Test func eligibilityIsIndependentOfNativeSourceAcceptanceAndJSONRejectsImages() throws {
        #expect(RichMarkdownPolicy.eligibility(source: "text", url: URL(fileURLWithPath: "/note.txt")) != nil)
        #expect(RichMarkdownPolicy.eligibility(source: "text", url: URL(fileURLWithPath: "/note.MD")) == nil)
        #expect(RichMarkdownPolicy.eligibility(source: String(repeating: "x", count: RichMarkdownPolicy.maximumSourceBytes + 1), url: url) != nil)
        #expect(DiskNoteStore.maximumBytes == 64 * 1024 * 1024)
        #expect(throws: (any Error).self) {
            _ = try RichMarkdownPolicy.validateJSON(["type": "doc", "content": [["type": "image", "attrs": ["src": "file:///secret"]]]])
        }
        #expect(!RichMarkdownPolicy.documentURL(URL(string: "https://editor/MilkdownIndex.html")))
        #expect(!RichMarkdownPolicy.documentURL(URL(string: "scribbit-milkdown://user@editor/MilkdownIndex.html")))
    }

    @Test func saveCopyCapturesBrowserSourceWithoutChangingOriginalBaseline() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-fixtures/rich-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.captureEditor = { _ in "- Captured copy" }
        let copy = directory.appendingPathComponent("copy.md")
        await model.saveCopy(to: copy)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "- Captured copy")
        #expect(store.writes == 0 && store.bytes == Data("Original\r\n".utf8))
        #expect(model.isDirty && model.isOpen)
    }

    @Test func untitledSaveAsUsesBarrierAndAnUnsafeSnapshotCreatesNoFile() async throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/test-fixtures/rich-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = NoteModel(session: NoteSession(store: DiskNoteStore()))
        model.openUntitled()
        model.captureEditor = { _ in throw RichMarkdownPolicy.failure("Unsafe") }
        let destination = directory.appendingPathComponent("note.md")
        #expect(await !model.saveUntitled(to: destination))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        model.captureEditor = { _ in "- [ ] Accepted task" }
        #expect(await model.saveUntitled(to: destination))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "- [ ] Accepted task")
        #expect(!model.isUntitled && !model.isDirty)
    }
}

@MainActor
struct MilkdownSettlementRegressionTests {
    @Test func closeFinalizesActualCapturedSourceBeforeClearingPresentation() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        let url = URL(fileURLWithPath: "/disposable/milkdown.md")
        #expect(await model.open(url))
        model.captureEditor = { _ in "Fresh Markdown" }
        var finished: String?
        model.finishEditor = { outcome, source in if outcome == .closed { finished = source } }
        #expect(await model.close())
        #expect(model.text.isEmpty)
        #expect(finished == "Fresh Markdown")
        #expect(store.bytes == Data("Fresh Markdown".utf8))
    }
}

@MainActor
struct EditorModeTransitionTests {
    private let url = URL(fileURLWithPath: "/disposable/note.md")

    @Test func richToSourceUsesLatestSnapshotWithoutSavingOrChangingFileBaseline() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.editorDidChange()
        model.captureEditor = { inspection in
            #expect(!inspection && model.isBusy)
            return "Newest unsaved rich edit\n"
        }
        var activated = false
        let switchedToSource = await model.changeEditorMode(toRich: false, importRich: { _, _ in
            Issue.record("Must not import while leaving rich")
            return false
        }, activateSource: { activated = true })
        #expect(switchedToSource)
        #expect(activated && model.text == "Newest unsaved rich edit\n")
        #expect(model.isDirty && !model.pendingEditorChanges && !model.isBusy)
        #expect(store.writes == 0 && store.bytes == Data("Original\r\n".utf8))
        model.captureEditor = nil
        await model.save()
        #expect(store.writes == 1 && !model.isDirty)
    }

    @Test func sourceToRichImportsNewestUnsavedTextWithoutSavingOrChangingDirtyBaseline() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.text = "Newest native composition\n"
        let switchedToRich = await model.changeEditorMode(toRich: true, importRich: { source, importedURL in
            #expect(model.isBusy && source == "Newest native composition\n" && importedURL == url)
            return true
        }, activateSource: { Issue.record("Must not activate source on rich import") })
        #expect(switchedToRich)
        #expect(model.text == "Newest native composition\n" && model.isDirty)
        #expect(store.writes == 0 && !model.isBusy)
        model.text = "Original\r\n"
        #expect(!model.isDirty) // Mode changes did not move the file baseline.
    }

    @Test func failedCaptureRetainsRichDraftAndUnlocksWithoutCallingSourceOrSaving() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        let accepted = model.text
        model.editorDidChange()
        model.captureEditor = { _ in throw CocoaError(.coderInvalidValue) }
        var retained = false
        model.finishEditor = { outcome, source in
            #expect(outcome == .retained && source == accepted)
            retained = true
        }
        let captureRejected = await !model.changeEditorMode(toRich: false, importRich: { _, _ in false },
            activateSource: { Issue.record("Failed snapshot must not deactivate rich") })
        #expect(captureRejected)
        #expect(retained && model.text == accepted && model.pendingEditorChanges && model.isDirty)
        #expect(model.error != nil && !model.isBusy && store.writes == 0)
    }

    @Test func rejectedImportKeepsSourceAndReasonAndDoesNotToggleOrWrite() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        model.text = "<custom>Keep source</custom>\n"
        let importRejected = await !model.changeEditorMode(toRich: true, importRich: { source, _ in
            #expect(source == model.text)
            model.error = "Unsupported source retained"
            return false
        }, activateSource: { Issue.record("Rejected import must retain source") })
        #expect(importRejected)
        #expect(model.text == "<custom>Keep source</custom>\n" && model.isDirty)
        #expect(model.error == "Unsupported source retained" && !model.isBusy && store.writes == 0)
    }

    @Test func busyTransitionRejectsReentryCloseAndFileSwitch() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        #expect(await model.open(url))
        let switchedToRich = await model.changeEditorMode(toRich: true, importRich: { _, _ in
            let reentryRejected = await !model.changeEditorMode(toRich: false, importRich: { _, _ in true },
                activateSource: { Issue.record("Reentrant source activation") })
            #expect(reentryRejected)
            #expect(await !model.close())
            #expect(await !model.open(URL(fileURLWithPath: "/disposable/other.md")))
            return true
        }, activateSource: {})
        #expect(switchedToRich)
        #expect(model.url == url && model.isOpen && !model.isDirty && store.writes == 0)
    }

    @Test func untitledModesStayRAMOnlyAndClosedOrResetCannotSwitch() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        let closedRejected = await !model.changeEditorMode(toRich: true, importRich: { _, _ in true }, activateSource: {})
        #expect(closedRejected)
        model.openUntitled()
        model.text = "Native draft"
        let switchedToRich = await model.changeEditorMode(toRich: true, importRich: { source, url in
            #expect(source == "Native draft" && url == nil)
            return true
        }, activateSource: {})
        #expect(switchedToRich)
        model.captureEditor = { _ in "Rich draft" }
        let switchedToSource = await model.changeEditorMode(toRich: false, importRich: { _, _ in false }, activateSource: {})
        #expect(switchedToSource)
        #expect(model.text == "Rich draft" && model.isUntitled && model.isDirty)
        model.resetInProgress = true
        let resetRejected = await !model.changeEditorMode(toRich: true, importRich: { _, _ in
            Issue.record("Reset may not import")
            return true
        }, activateSource: {})
        #expect(resetRejected)
        #expect(store.writes == 0 && store.reads == 0)
    }

    @Test func textFilesAndLargeSourceRemainInSourceWithPolicyReason() {
        #expect(RichMarkdownPolicy.eligibility(source: "Text", url: URL(fileURLWithPath: "/disposable/note.txt")) != nil)
        #expect(RichMarkdownPolicy.eligibility(source: String(repeating: "a", count: RichMarkdownPolicy.maximumSourceBytes + 1), url: url) != nil)
    }
}

@MainActor
struct GrownRichDraftPersistenceTests {
    @Test func grownDraftSwitchesToSourceAndSavesWithoutMovingBaselineOrTruncation() async {
        let store = RichSettlementStore()
        let model = NoteModel(session: NoteSession(store: store))
        let url = URL(fileURLWithPath: "/disposable/grown.md")
        #expect(await model.open(url))
        let grown = "\u{FEFF}" + String(repeating: "x", count: RichMarkdownPolicy.maximumSourceBytes + 32) + "\r\n"
        model.captureEditor = { _ in grown }
        model.editorDidChange()
        let switched = await model.changeEditorMode(toRich: false, importRich: { _, _ in false }, activateSource: {})
        #expect(switched && model.text == grown && model.isDirty && store.writes == 0)
        model.captureEditor = nil
        await model.save()
        #expect(store.bytes == Data(grown.utf8) && store.writes == 1 && !model.isDirty)
    }
}
