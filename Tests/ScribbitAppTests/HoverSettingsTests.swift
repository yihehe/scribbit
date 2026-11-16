import Foundation
import Testing
@testable import Scribbit
import ScribbitCore

private final class HoverSettingsStore: NoteStore {
    func read(_ url: URL) throws -> Data { Data("note".utf8) }
    func save(_ data: Data, to url: URL, replacing baseline: Data) throws {}
}

struct HoverSettingsTests {
    @Test @MainActor func isolatedSettingUsesShorterDefaultAndNormalizesWrites() {
        let settings = AppSettings(isolated: true)
        #expect(settings.hoverDelay == HoverDelay.defaultValue)
        settings.hoverDelay = 0.35
        #expect(abs(settings.hoverDelay - 0.35) < 0.000_001)
        settings.hoverDelay = 0
        #expect(settings.hoverDelay == 0)
        #expect(HoverDelay.label(settings.hoverDelay) == "0 ms")
        settings.hoverDelay = 100
        #expect(settings.hoverDelay == HoverDelay.range.upperBound)
        settings.hoverDelay = .nan
        #expect(settings.hoverDelay == HoverDelay.defaultValue)
        settings.hoverDelay = .infinity
        #expect(settings.hoverDelay == HoverDelay.defaultValue)
        settings.hoverDelay = 0.124
        #expect(settings.hoverDelay == 0.1)
        #expect(AppSettings(isolated: true).hoverDelay == HoverDelay.defaultValue)
    }

    @Test @MainActor func hoverPreferenceDoesNotChangeOtherSettings() {
        let settings = AppSettings(isolated: true)
        settings.animationSpeed = 1.75
        settings.indicator = true
        settings.hoverDelay = 0.5
        #expect(settings.animationSpeed == 1.75)
        #expect(settings.indicator)
        settings.animationSpeed = 2
        #expect(settings.hoverDelay == 0.5)
        #expect(!settings.didOfferLogin)
        #expect(settings.bookmark == nil)
    }

    @Test @MainActor func fileLifecycleDoesNotResetConfiguredHoverDelay() async {
        let model = NoteModel(session: NoteSession(store: HoverSettingsStore()))
        #expect(model.hoverDelay == HoverDelay.defaultValue)
        model.hoverDelay = 0.5
        let url = URL(fileURLWithPath: "/example/hover-settings.md")
        _ = await model.open(url)
        #expect(model.hoverDelay == 0.5)
        await model.reload()
        #expect(model.hoverDelay == 0.5)
        _ = await model.close()
        #expect(model.hoverDelay == 0.5)
        _ = await model.open(url)
        #expect(model.hoverDelay == 0.5)
    }
}
