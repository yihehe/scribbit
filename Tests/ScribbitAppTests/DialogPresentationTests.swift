import AppKit
import Testing

struct DialogPresentationTests {
    @Test func standaloneModalLevelsAreBelowTheNotchPanelLevel() {
        // Constant policy check only: no NSApplication, windows, or GUI launch.
        #expect(NSWindow.Level.normal.rawValue < NSWindow.Level.statusBar.rawValue)
        #expect(NSWindow.Level.modalPanel.rawValue < NSWindow.Level.statusBar.rawValue)
    }
}
