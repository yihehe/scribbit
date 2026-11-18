import AppKit
import ScribbitCore

@main
struct ScribbitApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        if Bundle.main.object(forInfoDictionaryKey: "ScribbitMilkdownCandidate") as? Bool == true
            || CommandLine.arguments.dropFirst().contains("--milkdown-candidate") {
            // Evaluation identity uses RAM preferences and cannot register login.
            let delegate = AppDelegate(richMarkdown: true, ephemeralPreferences: true)
            app.delegate = delegate
            withExtendedLifetime(delegate) { app.run() }
            return
        }
        if (3...4).contains(CommandLine.arguments.count), CommandLine.arguments[1] == "--smoke-test" {
            guard CommandLine.arguments.count == 3 || CommandLine.arguments[3] == "native" else {
                fputs("Only the native editor is supported\n", stderr); exit(64)
            }
            let harness = SmokeTestDelegate(output: URL(fileURLWithPath: CommandLine.arguments[2]))
            app.delegate = harness
            withExtendedLifetime(harness) { app.run() }
            return
        }
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--benchmark-editor" {
            guard CommandLine.arguments[2] == "native" else { exit(64) }
            let benchmark = EditorBenchmarkDelegate(output: URL(fileURLWithPath: CommandLine.arguments[3]))
            app.delegate = benchmark
            withExtendedLifetime(benchmark) { app.run() }
            return
        }
        let delegate = AppDelegate(richMarkdown: true)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
