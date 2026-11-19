import AppKit
import ScribbitCore

@main
struct ScribbitApp {
    @MainActor static func main() {
        let mode: LaunchMode
        do {
            mode = try LaunchMode.parse(Array(CommandLine.arguments.dropFirst()),
                candidateBundle: Bundle.main.object(forInfoDictionaryKey: "ScribbitMilkdownCandidate") as? Bool == true)
        } catch {
            fputs(LaunchMode.usage + "\n", stderr)
            exit(64)
        }
        let app = NSApplication.shared
        switch mode {
        case let .smoke(output, .rich):
            let harness = RichEditorSmoke(output: URL(fileURLWithPath: output))
            app.delegate = harness
            withExtendedLifetime(harness) { app.run() }
            return
        case .candidate:
            // Evaluation identity uses RAM preferences and cannot register login.
            let delegate = AppDelegate(richMarkdown: true, ephemeralPreferences: true)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        case let .smoke(output, .native):
            let harness = SmokeTestDelegate(output: URL(fileURLWithPath: output))
            app.delegate = harness
            withExtendedLifetime(harness) { app.run() }
            return
        case let .benchmark(output):
            let benchmark = EditorBenchmarkDelegate(output: URL(fileURLWithPath: output))
            app.delegate = benchmark
            withExtendedLifetime(benchmark) { app.run() }
            return
        case .normal:
            let delegate = AppDelegate(richMarkdown: true)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
        }
    }
}
