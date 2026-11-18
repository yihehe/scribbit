import Foundation
import Testing
@testable import Scribbit

struct RichSnapshotAuthorityTests {
    private func document(_ text: String?) -> [String: Any] {
        var paragraph: [String: Any] = ["type": "paragraph"]
        if let text { paragraph["content"] = [["type": "text", "text": text]] }
        return ["type": "doc", "content": [paragraph]]
    }
    private func bytes(_ document: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    @Test func exactNativeBaselineReusesOriginalBytesWithoutSerializedSource() throws {
        let doc = document("A * literal")
        for source in ["A * literal", "\u{FEFF}A * literal\r\n\r\n", "  A * literal  \n"] {
            let result = try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: bytes(doc),
                originalSource: source, serializedSource: nil, sourceHasBOM: true, sourceUsesCRLF: true)
            #expect(Data(result.source.utf8) == Data(source.utf8))
        }
        let empty = document(nil)
        let result = try RichMarkdownPolicy.snapshotSource(document: empty, committedDocument: bytes(empty),
            originalSource: "", serializedSource: nil, sourceHasBOM: false, sourceUsesCRLF: false)
        #expect(result.source.isEmpty)
    }
    @Test func missingSourceCannotAuthorizeChangedOrUncommittedDocument() throws {
        let committed = document("Original")
        for baseline in [try bytes(committed), nil] {
            #expect(throws: (any Error).self) {
                _ = try RichMarkdownPolicy.snapshotSource(document: document("Changed"), committedDocument: baseline,
                    originalSource: "Original", serializedSource: nil, sourceHasBOM: false, sourceUsesCRLF: false)
            }
        }
    }
    @Test func editedSourceStillRequiresExplicitSnapshotAndRetainsLineEndingPolicy() throws {
        let result = try RichMarkdownPolicy.snapshotSource(document: document("Changed"),
            committedDocument: bytes(document("Original")), originalSource: "Original",
            serializedSource: "Changed\n", sourceHasBOM: true, sourceUsesCRLF: true)
        #expect(result.source == "\u{FEFF}Changed\r\n")
        #expect(result.document == (try bytes(document("Changed"))))
    }
    @Test func emptySerializedSourceCannotEraseNonemptyDocumentButAllowsActualDeletion() throws {
        #expect(throws: (any Error).self) {
            _ = try RichMarkdownPolicy.snapshotSource(document: document("Changed"), committedDocument: bytes(document("Original")),
                originalSource: "Original", serializedSource: "", sourceHasBOM: false, sourceUsesCRLF: false)
        }
        let deleted = try RichMarkdownPolicy.snapshotSource(document: document(nil), committedDocument: bytes(document("Original")),
            originalSource: "Original", serializedSource: "", sourceHasBOM: false, sourceUsesCRLF: false)
        #expect(deleted.source == "")
    }
}

struct MilkdownSchemaAuthorityTests {
    @Test func actualMilkdownNodesMarksAreAcceptedButForeignSchemaIsRejected() throws {
        let document: [String: Any] = ["type": "doc", "content": [
            ["type": "heading", "attrs": ["id": "", "level": 2], "content": [["type": "text", "text": "Heading"]]],
            ["type": "bullet_list", "attrs": ["spread": false], "content": [
                ["type": "list_item", "attrs": ["checked": false, "label": "•", "listType": "bullet", "spread": false], "content": [
                    ["type": "paragraph", "content": [["type": "text", "text": "Task", "marks": [["type": "strong"], ["type": "link", "attrs": ["href": "https://example.invalid", "title": "Title"]]]]]]
                ]]
            ]],
            ["type": "code_block", "attrs": ["language": "python"], "content": [["type": "text", "text": "value\n\n"]]]
        ]]
        #expect(try !RichMarkdownPolicy.validateJSON(document).isEmpty)
        for type in ["bulletList", "codeBlock", "image", "html", "iframe"] {
            #expect(throws: (any Error).self) {
                _ = try RichMarkdownPolicy.validateJSON(["type": "doc", "content": [["type": type]]])
            }
        }
    }
}

struct RichEditorPageLoadTests {
    private let boot = URL(string: "scribbit-milkdown://editor/MilkdownIndex.html?token=boot-nonce")!
    private let recovery = URL(string: "scribbit-milkdown://editor/MilkdownIndex.html?token=recovery-nonce")!

    @Test func onlyArmedExactProgrammaticMainFrameLoadIsAdmittedOnce() {
        var load = RichEditorPageLoad()
        let admitted1 = !load.admit(boot, isMainFrame: true, isProgrammatic: true)
        #expect(admitted1)
        load.arm(boot)
        for blocked in [
            URL(string: "scribbit-milkdown://editor/MilkdownIndex.html"),
            URL(string: "scribbit-milkdown://editor/MilkdownIndex.html?token=changed"),
            URL(string: "scribbit-milkdown://editor/MilkdownIndex.html?token=boot-nonce#link"),
            URL(string: "https://example.invalid/MilkdownIndex.html"), nil
        ] {
            let admitted2 = !load.admit(blocked, isMainFrame: true, isProgrammatic: true)
            #expect(admitted2)
            #expect(load.pendingURL == boot)
        }
        // User links/reloads and subframes cannot consume the native allowance.
        let admitted3 = !load.admit(boot, isMainFrame: true, isProgrammatic: false)
        #expect(admitted3)
        let admitted4 = !load.admit(boot, isMainFrame: false, isProgrammatic: true)
        #expect(admitted4)
        let admitted5 = load.admit(boot, isMainFrame: true, isProgrammatic: true)
        #expect(admitted5)
        #expect(load.pendingURL == nil)
        let admitted6 = !load.admit(boot, isMainFrame: true, isProgrammatic: true)
        #expect(admitted6)
    }

    @Test func recoveryArmsANewNonceAndOldOrReplayedRequestsRemainDenied() {
        var load = RichEditorPageLoad()
        load.arm(boot)
        let admitted7 = load.admit(boot, isMainFrame: true, isProgrammatic: true)
        #expect(admitted7)
        load.arm(recovery)
        let admitted8 = !load.admit(boot, isMainFrame: true, isProgrammatic: true)
        #expect(admitted8)
        let admitted9 = load.admit(recovery, isMainFrame: true, isProgrammatic: true)
        #expect(admitted9)
        let admitted10 = !load.admit(recovery, isMainFrame: true, isProgrammatic: true)
        #expect(admitted10)
    }
}

struct RichSourceLimitSeparationTests {
    @Test func grownSourceAboveAdmissionThresholdRetainsAllBytesIncludingBOMAndCRLF() throws {
        let source = String(repeating: "x", count: RichMarkdownPolicy.maximumSourceBytes + 32) + "\n"
        let doc: [String: Any] = ["type": "doc", "content": [["type": "paragraph", "content": [["type": "text", "text": "Changed"]]]]]
        let result = try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: nil,
            originalSource: "Original", serializedSource: source, sourceHasBOM: true, sourceUsesCRLF: true)
        #expect(result.source == "\u{FEFF}" + source.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(result.source.utf8.count > RichMarkdownPolicy.maximumSourceBytes)
        #expect(RichMarkdownPolicy.eligibility(source: result.source, url: nil) != nil)
        #expect(RichMarkdownPolicy.maximumExportSourceBytes == 64 * 1024 * 1024)
    }
}

struct RichCanonicalQuotaEncodingTests {
    private func document(_ text: String) -> [String: Any] {
        ["type": "doc", "content": [["type": "paragraph", "content": [["type": "text", "text": text]]]]]
    }
    @Test func canonicalQuotaMatchesJavaScriptSlashControlAndUnicodeEncoding() throws {
        let unit = "/🐸\u{2028}\u{2029}\u{0008}\u{000C}\n\r\t\"\\"
        // JSON.stringify leaves slash/Unicode literal and uses these short escapes.
        let escapedUnit = "/🐸\u{2028}\u{2029}\\b\\f\\n\\r\\t\\\"\\\\"
        let unitBytes = escapedUnit.utf8.count
        let overhead = try JSONSerialization.data(withJSONObject: document(""), options: [.withoutEscapingSlashes]).count
        let quota = RichMarkdownPolicy.maximumDocumentBytes
        let repeats = (quota - overhead) / unitBytes
        let text = String(repeating: unit, count: repeats) + String(repeating: "x", count: quota - overhead - repeats * unitBytes)
        let exact = document(text)
        let encoded = try JSONSerialization.data(withJSONObject: exact, options: [.withoutEscapingSlashes])
        #expect(encoded.count == quota)
        #expect(try !RichMarkdownPolicy.validateJSON(exact).isEmpty)
        #expect(throws: (any Error).self) { _ = try RichMarkdownPolicy.validateJSON(document(text + "x")) }
        let canonical = try JSONSerialization.data(withJSONObject: exact, options: [.sortedKeys, .withoutEscapingSlashes])
        let source = "Unchanged slash/control/Unicode source"
        let result = try RichMarkdownPolicy.snapshotSource(document: exact, committedDocument: canonical,
            originalSource: source, serializedSource: nil, sourceHasBOM: false, sourceUsesCRLF: false)
        #expect(result.source == source)
    }
    @Test func slashHeavyGrownRichDocumentCanExportAndReuseItsCanonicalBaseline() throws {
        let text = String(repeating: "/", count: 1_200_000)
        let doc = document(text)
        let escapedSize = try JSONSerialization.data(withJSONObject: doc).count
        #expect(escapedSize > RichMarkdownPolicy.maximumDocumentBytes)
        let result = try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: nil,
            originalSource: "Original", serializedSource: text + "\n", sourceHasBOM: true, sourceUsesCRLF: true)
        #expect(result.source == "\u{FEFF}" + text + "\r\n")
        let unchanged = try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: result.document,
            originalSource: result.source, serializedSource: nil, sourceHasBOM: true, sourceUsesCRLF: true)
        #expect(unchanged.source == result.source)
    }
}
