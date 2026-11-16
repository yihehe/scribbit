import Foundation
import CryptoKit
import Darwin

// Compiled with the production core sources, never linked into the app.
private final class CountedDiskStore: NoteStore {
    let disk = DiskNoteStore()
    var reads = 0
    var saves = 0
    func read(_ url: URL) throws -> Data { reads += 1; return try disk.read(url) }
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws {
        saves += 1
        try disk.save(data, to: url, replacing: baseline)
    }
}

private func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    return sorted[max(0, min(sorted.count - 1, Int(ceil(fraction * Double(sorted.count))) - 1))]
}

private func cpuMicroseconds() -> Double {
    var usage = rusage()
    precondition(getrusage(RUSAGE_SELF, &usage) == 0)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec)
}

private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    precondition(status == KERN_SUCCESS)
    return info.resident_size
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: "FileWatchingBenchmark", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
struct FileWatchingBenchmark {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--self-test" {
            try selfTest(URL(fileURLWithPath: args[1]))
            print("BENCHMARK_SELF_TEST_PASS")
            return
        }
        guard args.count == 7, let size = Int(args[3]), let iterations = Int(args[4]),
              let warmups = Int(args[5]), let idleSeconds = Double(args[6]),
              size > 0, size <= DiskNoteStore.maximumBytes, iterations > 0, warmups >= 0,
              ["disk", "watched"].contains(args[0]), ["store", "session"].contains(args[1]),
              ["quiet", "save", "external", "sibling"].contains(args[2]) else {
            fatalError("Usage: binary disk|watched store|session quiet|save|external|sibling bytes iterations warmups idleSeconds; cwd must be disposable fixture directory")
        }
        let mode = args[0], layer = args[1], scenario = args[2]
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let file = directory.appendingPathComponent("note.md")
        let sibling = directory.appendingPathComponent("unrelated-file")
        // Stream fixture creation so a 64 MiB setup allocation does not pollute
        // the pre-warmup RSS baseline; file contents still enter the OS cache.
        try Data().write(to: file)
        let fixtureHandle = try FileHandle(forWritingTo: file)
        let chunk = Data(repeating: 0x61, count: min(size, 65536))
        var remaining = size
        while remaining > 0 {
            let count = min(remaining, chunk.count)
            try fixtureHandle.write(contentsOf: chunk.prefix(count))
            remaining -= count
        }
        try fixtureHandle.close()
        let underlying = CountedDiskStore()
        let store: NoteStore = mode == "watched" ? WatchedNoteStore(store: underlying) : underlying
        let session = NoteSession(store: store)
        var expected: UInt8 = 0x61
        var checksum = 0
        let baselineRSS = residentBytes()
        // Prime the selected note before each workload, like an earlier close.
        _ = try autoreleasepool { try store.read(file).count }

        func prepare() throws {
            guard scenario != "quiet" else { return }
            try autoreleasepool {
                switch scenario {
                case "save":
                    let baseline = try store.read(file)
                    var next = baseline
                    expected = expected == 0x61 ? 0x62 : 0x61
                    next[0] = expected
                    try store.save(next, to: file, replacing: baseline)
                case "external":
                    expected = expected == 0x61 ? 0x62 : 0x61
                    var next = Data(repeating: 0x61, count: size)
                    next[0] = expected
                    try next.write(to: file, options: .atomic)
                case "sibling": try Data([0x61]).write(to: sibling, options: .atomic)
                default: break
                }
            }
            // Untimed spacing, not a guarantee of notification delivery. Counts
            // report observed misses; do not assume each event arrived by now.
            Thread.sleep(forTimeInterval: 0.02)
        }

        func operation() throws -> Double {
            let openStart = DispatchTime.now().uptimeNanoseconds
            if layer == "store" {
                let data = try store.read(file)
                try check(data.count == size && data.first == expected, "Wrong store snapshot")
                checksum &+= data.count + Int(data.first!)
                return Double(DispatchTime.now().uptimeNanoseconds - openStart) / 1_000
            }
            try session.open(file)
            // Match both worker fingerprints in NoteModel.open/close. Excludes
            // main-actor scheduling, selection clamp, SwiftUI and native layout.
            let openedHash = SHA256.hash(data: Data(session.text.utf8))
            let opened = Double(DispatchTime.now().uptimeNanoseconds - openStart) / 1_000
            let source = session.text
            try check(source.utf8.count == size && source.utf8.first == expected, "Wrong session snapshot")
            try session.close()
            let closedHash = SHA256.hash(data: Data(source.utf8))
            checksum &+= Int(Array(openedHash)[0]) + Int(Array(closedHash)[0])
            try check(session.text.isEmpty && !session.isOpen, "Session did not close")
            return opened
        }

        for _ in 0..<warmups { try prepare(); _ = try autoreleasepool { try operation() } }
        let warmedHiddenRSS = residentBytes()
        let idleCPUStart = cpuMicroseconds()
        let idleStart = DispatchTime.now().uptimeNanoseconds
        if idleSeconds > 0 { Thread.sleep(forTimeInterval: idleSeconds) }
        let idleWall = Double(DispatchTime.now().uptimeNanoseconds - idleStart) / 1_000_000_000
        let idleCPU = cpuMicroseconds() - idleCPUStart
        var elapsed: [Double] = [], opened: [Double] = [], cpu: [Double] = []
        var measuredReads = 0
        for _ in 0..<iterations {
            try prepare()
            let priorReads = underlying.reads
            let cpuStart = cpuMicroseconds()
            let start = DispatchTime.now().uptimeNanoseconds
            let openTime = try autoreleasepool { try operation() }
            elapsed.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000)
            cpu.append(cpuMicroseconds() - cpuStart)
            opened.append(openTime)
            measuredReads += underlying.reads - priorReads
        }
        let result: [String: Any] = [
            "mode": mode, "layer": layer, "scenario": scenario, "bytes": size,
            "iterations": iterations, "warmups": warmups, "checksum": checksum,
            "thermal_state": ProcessInfo.processInfo.thermalState.rawValue,
            "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "median_us": percentile(elapsed, 0.5), "p95_us": percentile(elapsed, 0.95),
            "open_median_us": percentile(opened, 0.5), "open_p95_us": percentile(opened, 0.95),
            "cpu_median_us": percentile(cpu, 0.5), "cpu_p95_us": percentile(cpu, 0.95),
            "measured_reads": measuredReads, "all_reads": underlying.reads, "all_saves": underlying.saves,
            "baseline_rss_bytes": baselineRSS, "warmed_hidden_rss_bytes": warmedHiddenRSS,
            "final_hidden_rss_bytes": residentBytes(), "idle_wall_seconds": idleWall,
            "idle_cpu_us": idleCPU, "samples_us": elapsed, "open_samples_us": opened,
            "cpu_samples_us": cpu
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: json, encoding: .utf8)!)
        store.invalidateCache()
    }

    private static func selfTest(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try check(percentile([4, 1, 3, 2], 0.5) == 2, "Nearest-rank median")
        try check(percentile(Array(1...20).map(Double.init), 0.95) == 19, "Nearest-rank p95")
        let file = directory.appendingPathComponent("note.md")
        let original = Data("first".utf8)
        try original.write(to: file)
        let disk = CountedDiskStore()
        let watched = WatchedNoteStore(store: disk)
        try check(try watched.read(file) == original, "Initial read")
        try check(try watched.read(file) == original && disk.reads == 1, "Unchanged hit")
        let saved = Data("saved".utf8)
        try watched.save(saved, to: file, replacing: original)
        try check(try watched.read(file) == saved && disk.reads == 2, "Own save misses")
        try original.write(to: file, options: .atomic)
        try check(try watched.read(file) == original && disk.reads == 3, "External replacement misses")
        watched.invalidateCache()
    }
}
