import AppKit
import SwiftUI
import Darwin
import ScribbitCore

/// Opt-in component comparison, deliberately excluding GIF/screenshot export,
/// login services, real notes and production preferences. Runs the native editor
/// in a fresh process with a non-focused editor.
@MainActor
final class EditorBenchmarkDelegate: NSObject, NSApplicationDelegate {
    let output: URL
    init(output: URL) { self.output = output }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            do { try await run(); print("EDITOR_BENCHMARK_PASS: native"); exit(0) }
            catch { fputs("EDITOR_BENCHMARK_FAIL: \(error)\n", stderr); exit(1) }
        }
    }
    private func rss() -> UInt64? {
        var info = mach_task_basic_info()
        let capacity = MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : nil
    }
    private func cpu() -> Double {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    private func settle(_ host: NSView, text: String) async throws -> EditorProbe {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        repeat {
            host.layoutSubtreeIfNeeded()
            if let editor = EditorProbe.find(in: host), editor.string.utf8.elementsEqual(text.utf8) {
                editor.view.displayIfNeeded()
                return editor
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw NSError(domain: "EditorBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Editor failed to display expected source"])
    }
    private func run() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let small = output.appendingPathComponent("small.md")
        let large = output.appendingPathComponent("boundary-2MiB.md")
        let smallSource = String(repeating: "- A small benchmark note.\n", count: 80)
        let line = "  - Benchmark words with a tab\tand value.\n"
        let largeData = Data(String(repeating: line, count: DiskNoteStore.maximumBytes / line.utf8.count + 1).utf8).prefix(DiskNoteStore.maximumBytes)
        let largeSource = String(data: largeData, encoding: .utf8)!
        try Data(smallSource.utf8).write(to: small, options: .atomic)
        try largeData.write(to: large, options: .atomic)
        let model = NoteModel()
        let start = ProcessInfo.processInfo.systemUptime
        guard await model.open(small) else { throw CocoaError(.fileReadUnknown) }
        let panel = NotePanel(contentRect: CGRect(x: 180, y: 180, width: 620, height: 460), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: NoteView(model: model, choose: {}, saveCopy: {}, reload: {}))
        panel.contentView = host
        panel.orderFrontRegardless()
        _ = try await settle(host, text: smallSource)
        let initialSeconds = ProcessInfo.processInfo.systemUptime - start
        try await Task.sleep(nanoseconds: 500_000_000)
        let visibleRSS = rss()
        let visibleCPUStart = cpu()
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let visibleCPU = cpu() - visibleCPUStart
        let cycleStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 {
            guard await model.close() else { throw CocoaError(.fileWriteUnknown) }
            panel.orderOut(nil)
            _ = try await settle(host, text: "")
            guard await model.open(small) else { throw CocoaError(.fileReadUnknown) }
            panel.orderFrontRegardless()
            _ = try await settle(host, text: smallSource)
        }
        let cycleSeconds = ProcessInfo.processInfo.systemUptime - cycleStart
        let cyclesRSS = rss()
        for _ in 0..<20 {
            model.preview = true
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 10_000_000)
            model.preview = false
            _ = try await settle(host, text: smallSource)
        }
        let previewRSS = rss()
        _ = await model.close()
        _ = try await settle(host, text: "")
        let largeStart = ProcessInfo.processInfo.systemUptime
        guard await model.open(large) else { throw CocoaError(.fileReadUnknown) }
        let editor = try await settle(host, text: largeSource)
        let largeSeconds = ProcessInfo.processInfo.systemUptime - largeStart
        let largeRSS = rss()
        let editStart = ProcessInfo.processInfo.systemUptime
        for index in 0..<5 {
            let changed = index.isMultiple(of: 2) ? "X" : "Y"
            editor.insertText(changed, replacementRange: NSRange(location: largeSource.utf16.count - 1, length: 1))
            let expected = String(largeSource.dropLast()) + changed
            _ = try await settle(host, text: expected)
        }
        let editSeconds = ProcessInfo.processInfo.systemUptime - editStart
        await model.reload()
        _ = try await settle(host, text: largeSource)
        guard await model.close() else { throw CocoaError(.fileWriteUnknown) }
        panel.orderOut(nil)
        _ = try await settle(host, text: "")
        try await Task.sleep(nanoseconds: 500_000_000)
        let hiddenRSS = rss()
        let hiddenCPUStart = cpu()
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let hiddenCPU = cpu() - hiddenCPUStart
        let report: [String: Any] = [
            "engine": "native",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "processor_count": ProcessInfo.processInfo.processorCount,
            "small_note_bytes": smallSource.utf8.count,
            "large_note_bytes": largeData.count,
            "initial_small_load_layout_seconds": initialSeconds,
            "small_visible_rss_bytes": visibleRSS.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "visible_unfocused_idle_5s_cpu_seconds": visibleCPU,
            "twenty_open_close_cycles_seconds": cycleSeconds,
            "after_cycles_rss_bytes": cyclesRSS.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "after_twenty_preview_cycles_rss_bytes": previewRSS.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "large_load_layout_seconds": largeSeconds,
            "large_rss_bytes": largeRSS.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "five_large_single_character_replacements_seconds": editSeconds,
            "after_large_close_rss_bytes": hiddenRSS.map { NSNumber(value: $0) as Any } ?? NSNull(),
            "hidden_idle_5s_cpu_seconds": hiddenCPU,
            "scope": "Component-only, non-focused editor; no notch animation, monitors, screenshots, GIFs, plugins or production preferences. 20 cycles are not a leak proof. Fixtures remain allocated in this process."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("metrics.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
