import Foundation
import Testing
@testable import Scribbit

struct AppMetadataTests {
    /// Read the resource that build-app.sh actually packages, not the test
    /// runner's bundle. Verify the identity shipped in the app bundle.
    private func metadata() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        return try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    @Test func renamedAppHasConsistentDisplayAndExecutableNames() throws {
        let info = try metadata()
        #expect(info["CFBundleName"] as? String == "Scribbit")
        #expect(info["CFBundleDisplayName"] as? String == "Scribbit")
        #expect(info["CFBundleExecutable"] as? String == "Scribbit")
        #expect(info["CFBundleIconFile"] as? String == "AppIcon")
    }

    @Test func appUsesScribbitIdentityAndAccessoryMode() throws {
        let info = try metadata()
        #expect(info["CFBundleIdentifier"] as? String == "com.stephenhe.Scribbit")
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["LSMinimumSystemVersion"] as? String == "14.0")
    }
    @Test func aboutUsesThePackagedDisplayNameAndVersion() throws {
        let about = AboutInfo(infoDictionary: try metadata())
        #expect(about.name == "Scribbit")
        #expect(about.version == "0.5.2")
        #expect(about.versionText == "Version 0.5.2")
    }
    @Test func aboutOmitsBlankVersionWithoutAPlaceholderOrHelpDump() {
        let about = AboutInfo(infoDictionary: [
            "CFBundleDisplayName": " ",
            "CFBundleName": " Scribbit ",
            "CFBundleShortVersionString": "\n"
        ])
        #expect(about.name == "Scribbit")
        #expect(about.version == nil && about.versionText.isEmpty)
        #expect(AboutInfo(infoDictionary: nil).name == "Scribbit")
    }
}
