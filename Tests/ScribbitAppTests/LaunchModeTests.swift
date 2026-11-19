import Testing
@testable import Scribbit

struct LaunchModeTests {
    @Test func ordinaryLaunchHonorsBundleIdentityAndSystemArguments() throws {
        #expect(try LaunchMode.parse([], candidateBundle: false) == .normal)
        #expect(try LaunchMode.parse([], candidateBundle: true) == .candidate)
        #expect(try LaunchMode.parse(["-NSDocumentRevisionsDebugMode", "YES"], candidateBundle: false) == .normal)
        #expect(try LaunchMode.parse(["--milkdown-candidate"], candidateBundle: false) == .candidate)
    }
    @Test func explicitHarnessOverridesCandidateBundleWithoutLaunchingNormalApp() throws {
        for candidate in [true, false] {
            #expect(try LaunchMode.parse(["--smoke-test", "fixture output"], candidateBundle: candidate)
                    == .smoke(output: "fixture output", engine: .native))
            #expect(try LaunchMode.parse(["--smoke-test", "out", "rich"], candidateBundle: candidate)
                    == .smoke(output: "out", engine: .rich))
            #expect(try LaunchMode.parse(["--benchmark-editor", "native", "out"], candidateBundle: candidate)
                    == .benchmark(output: "out"))
        }
    }
    @Test func malformedOwnedFlagsNeverBecomeNormalStartup() {
        let invalid = [
            ["--smoke-test"], ["--smoke-test", ""], ["--smoke-test", "   "],
            ["--smoke-test", "out", "unknown"], ["--smoke-test", "out", "native", "extra"],
            ["--benchmark-editor"], ["--benchmark-editor", "native"],
            ["--benchmark-editor", "rich", "out"], ["--benchmark-editor", "native", ""],
            ["--milkdown-candidate", "extra"], ["--smoke-test", "--milkdown-candidate"],
            ["other", "--smoke-test", "out"],
        ]
        for candidate in [true, false] {
            for arguments in invalid {
                #expect(throws: LaunchMode.InvalidArguments.self) {
                    try LaunchMode.parse(arguments, candidateBundle: candidate)
                }
            }
        }
    }
}
