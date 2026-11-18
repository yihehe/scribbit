import AppKit
import Combine
import CryptoKit
import SwiftUI
import WebKit
import ScribbitCore

enum EditorSettlementOutcome: Equatable { case saved, closed, retained }

/// Only a native-requested page boot/recovery may replace the editor document.
/// Matching the resource path alone would also admit user links and reloads,
/// destroying a live unsaved WebKit document.
struct RichEditorPageLoad {
    private(set) var pendingURL: URL?
    mutating func arm(_ url: URL) { pendingURL = url }
    mutating func admit(_ url: URL?, isMainFrame: Bool, isProgrammatic: Bool) -> Bool {
        guard isMainFrame, isProgrammatic, let url,
              RichMarkdownPolicy.documentURL(url), url == pendingURL else { return false }
        pendingURL = nil
        return true
    }
}

enum RichMarkdownPolicy {
    static let scheme = "scribbit-milkdown"
    static let host = "editor"
    static let maximumSourceBytes = 1 * 1_024 * 1_024
    static let maximumExportSourceBytes = DiskNoteStore.maximumBytes
    static let maximumDocumentBytes = 2 * 1_024 * 1_024
    static func documentURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == scheme && url.host == host && url.path == "/MilkdownIndex.html"
            && url.user == nil && url.password == nil && url.port == nil
    }
    static func eligibility(source: String, url: URL?) -> String? {
        if let url, url.pathExtension.lowercased() != "md" { return "Plain-text files remain in the native source editor." }
        if source.utf8.count > maximumSourceBytes { return "Files larger than 1 MiB open in the native source editor." }
        return nil
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "ScribbitRichMarkdown", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    static func validateJSON(_ value: Any) throws -> [String: Any] {
        guard let doc = value as? [String: Any], doc["type"] as? String == "doc" else { throw failure("Invalid rich document.") }
        let allowed = Set(["doc", "paragraph", "text", "heading", "blockquote", "bullet_list", "ordered_list",
                           "list_item", "code_block", "hardbreak", "hr", "table", "table_header_row", "table_row", "table_header", "table_cell"])
        func check(_ node: [String: Any], depth: Int) throws {
            guard depth < 100, let type = node["type"] as? String, allowed.contains(type) else { throw failure("Unsupported rich node.") }
            if type == "text", node["text"] as? String == nil { throw failure("Malformed rich text.") }
            if let value = node["marks"] {
                guard let marks = value as? [[String: Any]] else { throw failure("Malformed rich marks.") }
                guard marks.allSatisfy({ ["strong", "emphasis", "strike_through", "inlineCode", "link"].contains($0["type"] as? String ?? "") }) else { throw failure("Unsupported rich mark.") }
            }
            if let value = node["content"] {
                guard let children = value as? [[String: Any]] else { throw failure("Malformed rich content.") }
                for child in children { try check(child, depth: depth + 1) }
            }
        }
        try check(doc, depth: 0)
        let bytes = try JSONSerialization.data(withJSONObject: doc, options: [.withoutEscapingSlashes])
        guard bytes.count <= maximumDocumentBytes else { throw failure("Rich document exceeds its 2 MiB canonical JSON bound.") }
        return doc
    }
    /// Only native's own exact committed tree authorizes reusing source bytes.
    /// A browser hint, missing source, or revision number alone is insufficient.
    static func snapshotSource(document: [String: Any], committedDocument: Data?,
                               originalSource: String, serializedSource: Any?,
                               sourceHasBOM: Bool, sourceUsesCRLF: Bool) throws -> (source: String, document: Data) {
        let doc = try validateJSON(document)
        let data = try JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys, .withoutEscapingSlashes])
        let unchanged = committedDocument != nil && data == committedDocument
        var source: String
        if unchanged { source = originalSource }
        else {
            guard let serialized = serializedSource as? String,
                  serialized.utf8.count <= maximumExportSourceBytes else { throw failure("Invalid rich source snapshot. The draft is retained.") }
            if serialized.isEmpty {
                let empty: [String: Any] = ["type": "doc", "content": [["type": "paragraph"]]]
                guard data == (try JSONSerialization.data(withJSONObject: empty, options: [.sortedKeys, .withoutEscapingSlashes])) else {
                    throw failure("Empty Markdown cannot replace a nonempty rich document. The draft is retained.")
                }
            }
            source = serialized
            if sourceUsesCRLF { source = source.replacingOccurrences(of: "\n", with: "\r\n") }
            if sourceHasBOM { source = "\u{FEFF}" + source }
        }
        guard source.utf8.count <= maximumExportSourceBytes else {
            throw failure("Edited source exceeds the 64 MiB file limit. The rich draft is retained; Undo the last edit.")
        }
        return (source, data)
    }
}

/// Concrete editor integration at the existing native/web boundary, not a
/// replacement for NoteSession or NoteStore. It never reads or writes files.
@MainActor
final class RichMarkdownEditor: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published private(set) var active = false
    @Published private(set) var fallbackReason: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var needsRecovery = false
    var changed: (Bool) -> Void = { _ in }
    var failed: (String) -> Void = { _ in }
    private(set) var web: WKWebView!
    private var token = UUID().uuidString
    private var pageLoad = RichEditorPageLoad()
    private var generation = UUID().uuidString
    private var revision = 0
    private var originalSource = ""
    private var sourceHasBOM = false
    private var sourceUsesCRLF = false
    private var pageReady = false
    private var readyWaiter: CheckedContinuation<Void, Error>?
    private var loadWaiter: CheckedContinuation<Bool, Never>?
    private var flushWaiter: CheckedContinuation<String?, Error>?
    private var flushID: String?
    private var flushInspection = false
    private var timer: Task<Void, Never>?
    private var mirror: [String: Any]?
    private var mirrorRevision = 0
    private var committedDocument: Data?
    private var capturedDocument: Data?
    private var readOnly = false
    private var position: [String: Any]?
    private var identity = ""
    private var positionCheckpoint: (identity: String, fingerprint: Data, position: [String: Any])?

    func createView() -> WKWebView {
        if let web { return web }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.setURLSchemeHandler(RichResourceHandler(bundle: BrandAssets.resourceBundle), forURLScheme: RichMarkdownPolicy.scheme)
        config.userContentController.add(self, name: "richEditor")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setAccessibilityLabel("Rich Markdown note")
        loadPage()
        return web
    }
    private func loadPage() {
        pageReady = false
        // A fresh page nonce also rejects messages queued by the old process
        // after a crash; note generations change only for explicit note actions.
        token = UUID().uuidString
        let url = URL(string: "\(RichMarkdownPolicy.scheme)://editor/MilkdownIndex.html?token=\(token)")!
        pageLoad.arm(url)
        web.load(URLRequest(url: url))
    }
    private func waitForPage() async throws {
        if pageReady { return }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiter = continuation
            let expectedGeneration = generation
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                guard let self, self.generation == expectedGeneration, self.readyWaiter != nil else { return }
                self.abort(RichMarkdownPolicy.failure("Rich editor did not become ready. Use the native source editor."))
            }
        }
    }
    func prepare(source: String, url: URL?) async {
        invalidate(preservePosition: true)
        fallbackReason = RichMarkdownPolicy.eligibility(source: source, url: url)
        guard fallbackReason == nil else { return }
        identity = url?.absoluteString ?? "untitled"
        let sourceFingerprint = await Self.fingerprint(source)
        var restored: [String: Any]?
        if let checkpoint = positionCheckpoint, checkpoint.identity == identity,
           checkpoint.fingerprint == sourceFingerprint {
            restored = checkpoint.position
        }
        originalSource = source
        sourceHasBOM = source.hasPrefix("\u{FEFF}")
        sourceUsesCRLF = source.contains("\r\n")
        revision = 0; mirrorRevision = 0
        _ = createView()
        do {
            try await waitForPage()
            let currentGeneration = generation
            let clean = sourceHasBOM ? String(source.dropFirst()) : source
            let accepted: Bool = await withCheckedContinuation { continuation in
                loadWaiter = continuation
                timeoutLoad()
                web.callAsyncJavaScript("window.scribbit.load(payload)", arguments: ["payload": [
                    "source": clean, "generation": currentGeneration, "readOnly": readOnly,
                    "position": restored ?? [:]
                ]], in: nil, in: .page) { [weak self] result in
                    guard let self, self.generation == currentGeneration, self.loadWaiter != nil else { return }
                    if case .failure(let error) = result { self.abort(error) }
                }
            }
            guard currentGeneration == generation else { return }
            active = accepted
            if !accepted {
                // A rejected/timed-out import must not leave hidden source or
                // permit late browser changes to dirty the native fallback.
                let reason = fallbackReason
                invalidate(preservePosition: true)
                fallbackReason = reason
            }
        } catch {
            fallbackReason = error.localizedDescription
            let reason = fallbackReason
            invalidate(preservePosition: true)
            fallbackReason = reason
        }
    }
    private func timeoutLoad() {
        timer?.cancel()
        let expectedGeneration = generation
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.generation == expectedGeneration, self.loadWaiter != nil else { return }
            self.abort(RichMarkdownPolicy.failure("Rich import timed out; the original source is retained."))
        }
    }
    /// Called from NoteModel's one settlement seam, after it owns the busy gate.
    /// No current snapshot is synthesized from the last change notification.
    func capture(inspectionOnly: Bool = false) async throws -> String? {
        guard active else { return nil }
        if inspectionOnly && needsRecovery { changed(true); return nil }
        guard !needsRecovery else { throw RichMarkdownPolicy.failure("Restore the rich editor or explicitly discard its draft before closing.") }
        guard flushWaiter == nil else { throw RichMarkdownPolicy.failure("An editor snapshot is already pending.") }
        let id = UUID().uuidString
        flushID = id
        flushInspection = inspectionOnly
        let expectedGeneration = generation
        let committedTree = committedDocument.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let committed: Any
        if let committedTree { committed = ["generation": expectedGeneration, "document": committedTree] }
        else { committed = NSNull() }
        let capturedSource: String? = try await withCheckedThrowingContinuation { continuation in
            flushWaiter = continuation
            timer?.cancel()
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                guard let self, self.generation == expectedGeneration, self.flushID == id else { return }
                self.abort(RichMarkdownPolicy.failure("Editor snapshot timed out. Finish composition and retry; no file was written."))
            }
            web.callAsyncJavaScript("window.scribbit.flush(id, inspect, committed)", arguments: ["id": id, "inspect": inspectionOnly, "committed": committed], in: nil, in: .page) { [weak self] result in
                guard let self, self.generation == expectedGeneration, self.flushID == id else { return }
                if case .failure(let error) = result { self.abort(error) }
            }
        }
        if let capturedSource, let position {
            let fingerprint = await Self.fingerprint(capturedSource)
            positionCheckpoint = (identity, fingerprint, position)
        }
        return capturedSource
    }
    func finish(_ outcome: EditorSettlementOutcome, source: String) {
        guard active else { return }
        if outcome == .saved || outcome == .closed {
            if let capturedDocument { committedDocument = capturedDocument }
            originalSource = source
        }
        capturedDocument = nil
        if outcome != .closed { web?.evaluateJavaScript("window.scribbit?.unlock()", completionHandler: nil) }
    }
    private static func fingerprint(_ source: String) async -> Data {
        await Task.detached(priority: .userInitiated) { Data(SHA256.hash(data: Data(source.utf8))) }.value
    }
    func releaseClosedDocument() { invalidate(preservePosition: true) }
    func adoptIdentity(_ url: URL) { identity = url.absoluteString }
    func invalidate(preservePosition: Bool = false) {
        let previousGeneration = generation
        timer?.cancel(); timer = nil
        let cancellation = RichMarkdownPolicy.failure("The editor document changed.")
        readyWaiter?.resume(throwing: cancellation); readyWaiter = nil
        loadWaiter?.resume(returning: false); loadWaiter = nil
        flushWaiter?.resume(throwing: cancellation); flushWaiter = nil
        flushID = nil
        generation = UUID().uuidString
        active = false; canUndo = false; canRedo = false
        needsRecovery = false
        mirror = nil; originalSource = ""; position = nil
        committedDocument = nil; capturedDocument = nil
        if !preservePosition { positionCheckpoint = nil }
        web?.callAsyncJavaScript("window.scribbit?.clear(expected)", arguments: ["expected": previousGeneration], in: nil, in: .page, completionHandler: nil)
    }
    func deactivateToSource(discardingDraft: Bool = false) {
        invalidate(preservePosition: !discardingDraft)
        fallbackReason = nil
    }
    func focus() { guard active, !needsRecovery else { return }; web.evaluateJavaScript("window.scribbit?.focus()", completionHandler: nil) }
    func undo() { guard active else { return }; web.evaluateJavaScript("window.scribbit?.undo()", completionHandler: nil) }
    func redo() { guard active else { return }; web.evaluateJavaScript("window.scribbit?.redo()", completionHandler: nil) }
    func find(_ text: String) {
        guard active, !text.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.wraps = true
        web.find(text, configuration: configuration, completionHandler: { _ in })
    }
    func setReadOnly(_ value: Bool) {
        guard value != readOnly else { return }; readOnly = value
        web?.callAsyncJavaScript("window.scribbit?.readOnly(value)", arguments: ["value": value], in: nil, in: .page, completionHandler: nil)
    }
    func restore() {
        guard needsRecovery else { return }
        let recoveryGeneration = generation
        _ = createView()
        Task {
            do {
                try await waitForPage()
                guard needsRecovery, generation == recoveryGeneration else { return }
                generation = UUID().uuidString
                let restorationGeneration = generation
                if let mirror {
                    web.callAsyncJavaScript("window.scribbit.restore(payload)", arguments: ["payload": [
                        "generation": generation, "document": mirror, "revision": mirrorRevision
                    ]], in: nil, in: .page) { [weak self] result in
                        guard let self, self.generation == restorationGeneration, self.needsRecovery else { return }
                        if case .failure(let error) = result { self.abort(error) }
                    }
                } else {
                    failed("No acknowledged rich checkpoint is available. Copy any recoverable text, or explicitly discard the rich draft to use the retained Markdown source.")
                }
            } catch {
                if generation == recoveryGeneration, needsRecovery { failed(error.localizedDescription) }
            }
        }
    }
    private func abort(_ error: Error) {
        timer?.cancel(); timer = nil
        readyWaiter?.resume(throwing: error); readyWaiter = nil
        loadWaiter?.resume(returning: false); loadWaiter = nil
        flushWaiter?.resume(throwing: error); flushWaiter = nil
        flushID = nil
        web?.evaluateJavaScript("window.scribbit?.unlock()", completionHandler: nil)
        fallbackReason = error.localizedDescription
        failed(error.localizedDescription)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === web, message.frameInfo.isMainFrame,
              RichMarkdownPolicy.documentURL(message.frameInfo.request.url),
              message.frameInfo.securityOrigin.protocol == RichMarkdownPolicy.scheme,
              message.frameInfo.securityOrigin.host == RichMarkdownPolicy.host,
              let body = message.body as? [String: Any], body["token"] as? String == token,
              let type = body["type"] as? String else { return }
        if type == "ready" {
            guard !pageReady else { return }
            pageReady = true; timer?.cancel(); timer = nil
            readyWaiter?.resume(); readyWaiter = nil
            return
        }
        guard body["generation"] as? String == generation else { return }
        switch type {
        case "loaded":
            guard loadWaiter != nil else { return }
            timer?.cancel(); timer = nil
            var accepted = body["accepted"] as? Bool == true
            if accepted {
                if let value = body["document"], let document = try? RichMarkdownPolicy.validateJSON(value),
                   let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes]) {
                    committedDocument = data
                } else { accepted = false }
            }
            fallbackReason = accepted ? nil : body["reason"] as? String ?? "Unsupported Markdown; using source mode."
            loadWaiter?.resume(returning: accepted); loadWaiter = nil
        case "changed":
            guard let next = body["revision"] as? Int, next > revision else { return }
            revision = next
            let undo = body["canUndo"] as? Bool ?? false
            let redo = body["canRedo"] as? Bool ?? false
            if canUndo != undo { canUndo = undo }
            if canRedo != redo { canRedo = redo }
            changed(true)
        case "checkpoint":
            guard let next = body["revision"] as? Int, next >= mirrorRevision, next <= revision,
                  let value = body["document"], let doc = try? RichMarkdownPolicy.validateJSON(value) else { return }
            mirror = doc; mirrorRevision = next
        case "snapshot":
            guard let id = body["id"] as? String, id == flushID,
                  let next = body["revision"] as? Int, next >= revision,
                  let value = body["document"], let doc = try? RichMarkdownPolicy.validateJSON(value) else { return }
            timer?.cancel(); timer = nil
            if flushInspection {
                mirror = doc; mirrorRevision = next; revision = next
                let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys, .withoutEscapingSlashes])
                let unchanged = data != nil && data == committedDocument
                changed(!unchanged)
                flushID = nil
                flushWaiter?.resume(returning: unchanged ? originalSource : nil); flushWaiter = nil
                return
            }
            let acceptedSource: String
            let data: Data
            do {
                let accepted = try RichMarkdownPolicy.snapshotSource(document: doc, committedDocument: committedDocument,
                    originalSource: originalSource, serializedSource: body["source"],
                    sourceHasBOM: sourceHasBOM, sourceUsesCRLF: sourceUsesCRLF)
                acceptedSource = accepted.source
                data = accepted.document
            } catch {
                abort(error); return
            }
            mirror = doc; mirrorRevision = next; revision = next
            capturedDocument = data
            if let scroll = body["scroll"] as? Double, scroll.isFinite {
                var checkpoint: [String: Any] = ["scroll": max(0, scroll)]
                if let selection = body["selection"] as? [String: Int],
                   let from = selection["from"], let to = selection["to"], from >= 0, to >= 0 {
                    checkpoint["selection"] = ["from": from, "to": to]
                }
                position = checkpoint
            } else { position = nil }
            flushID = nil
            flushWaiter?.resume(returning: acceptedSource); flushWaiter = nil
        case "flushError":
            if body["id"] as? String == flushID { abort(RichMarkdownPolicy.failure(body["message"] as? String ?? "Unsafe Markdown conversion.")) }
        case "restored":
            guard needsRecovery, let restoredRevision = body["revision"] as? Int,
                  restoredRevision == mirrorRevision else { return }
            revision = restoredRevision; canUndo = false; canRedo = false
            needsRecovery = false; changed(true)
            failed("Restored the last acknowledged rich checkpoint. The latest edits/preedit may be missing; review before saving.")
        case "error": failed(body["message"] as? String ?? "Rich editor error.")
        default: break
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = webView === web && pageLoad.admit(navigationAction.request.url,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            isProgrammatic: navigationAction.navigationType == .other)
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        needsRecovery = true
        changed(true)
        abort(RichMarkdownPolicy.failure("The web editor stopped. Unsaved rich state is retained only through the last acknowledged RAM checkpoint. Restore or explicitly discard it; nothing was written."))
        pageReady = false
        loadPage()
    }
}

struct RichMarkdownView: NSViewRepresentable {
    @ObservedObject var editor: RichMarkdownEditor
    var readOnly: Bool
    func makeNSView(context: Context) -> WKWebView { editor.createView() }
    func updateNSView(_ view: WKWebView, context: Context) { editor.setReadOnly(readOnly) }
}

private final class RichResourceHandler: NSObject, WKURLSchemeHandler {
    private let bundle: Bundle
    private var active = Set<ObjectIdentifier>()
    init(bundle: Bundle) { self.bundle = bundle }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let key = ObjectIdentifier(task); active.insert(key)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result: Result<(URL, Data, String), Error>
            do {
                guard let url = task.request.url, url.scheme == RichMarkdownPolicy.scheme,
                      url.host == RichMarkdownPolicy.host else { throw RichMarkdownPolicy.failure("Blocked resource.") }
                let names = ["MilkdownIndex.html": "text/html", "MilkdownEditor.js": "text/javascript", "MilkdownStyle.css": "text/css"]
                let name = String(url.path.dropFirst())
                guard let mime = names[name], url.path == "/" + name,
                      let file = bundle.url(forResource: name, withExtension: nil) else { throw RichMarkdownPolicy.failure("Blocked resource.") }
                result = .success((url, try Data(contentsOf: file), mime))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { [self] in
                guard active.remove(key) != nil else { return }
                switch result {
                case let .success((url, data, mime)):
                    task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
                    task.didReceive(data); task.didFinish()
                case .failure(let error): task.didFailWithError(error)
                }
            }
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { active.remove(ObjectIdentifier(task)) }
}
