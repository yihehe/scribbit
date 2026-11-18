import AppKit
import Foundation
import CryptoKit
import Testing
@testable import Scribbit

@MainActor
struct MilkdownAssetsTests {
    @MainActor @Test func bundledOfflineResourcesMatchRecordedSourcesAndScheme() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifestURL = try #require(BrandAssets.resourceBundle.url(forResource: "MilkdownAssets", withExtension: "json"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let hashes = try #require(object["sha256"] as? [String: String])
        for (path, hash) in hashes {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash)
        }
        let html = try String(contentsOf: #require(BrandAssets.resourceBundle.url(forResource: "MilkdownIndex", withExtension: "html")), encoding: .utf8)
        #expect(html.contains("script-src \(RichMarkdownPolicy.scheme):"))
        #expect(html.contains("connect-src 'none'"))
        #expect(!html.contains("https://"))
    }
}
