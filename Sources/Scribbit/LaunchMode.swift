import Foundation

/// Resolve app-owned flags before constructing NSApplication or reading settings.
/// A malformed test command must never fall through to normal startup.
enum LaunchMode: Equatable {
    enum SmokeEngine: String { case native, rich }
    case normal, candidate
    case smoke(output: String, engine: SmokeEngine)
    case benchmark(output: String)

    static let usage = "Usage: Scribbit [--milkdown-candidate | --smoke-test OUTPUT [native|rich] | --benchmark-editor native OUTPUT]"
    enum InvalidArguments: Error { case invalid }

    static func parse(_ arguments: [String], candidateBundle: Bool) throws -> LaunchMode {
        func output(_ value: String) throws -> String {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !value.hasPrefix("--") else { throw InvalidArguments.invalid }
            return value
        }
        switch arguments.first {
        case "--smoke-test":
            guard (2...3).contains(arguments.count) else { throw InvalidArguments.invalid }
            guard let engine = SmokeEngine(rawValue: arguments.count == 3 ? arguments[2] : "native")
            else { throw InvalidArguments.invalid }
            return .smoke(output: try output(arguments[1]), engine: engine)
        case "--benchmark-editor":
            guard arguments.count == 3, arguments[1] == "native" else { throw InvalidArguments.invalid }
            return .benchmark(output: try output(arguments[2]))
        case "--milkdown-candidate":
            guard arguments.count == 1 else { throw InvalidArguments.invalid }
            return .candidate
        default:
            let owned = ["--smoke-test", "--benchmark-editor", "--milkdown-candidate"]
            guard !arguments.contains(where: owned.contains) else { throw InvalidArguments.invalid }
            // Other arguments may belong to AppKit/LaunchServices, not our CLI.
            return candidateBundle ? .candidate : .normal
        }
    }
}
