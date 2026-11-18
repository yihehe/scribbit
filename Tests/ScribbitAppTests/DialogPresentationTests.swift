import AppKit
import Testing
@testable import Scribbit

struct DialogPresentationTests {
    @Test func standaloneModalLevelsAreBelowTheNotchPanelLevel() {
        // Constant policy check only: no NSApplication, windows, or GUI launch.
        #expect(NSWindow.Level.normal.rawValue < NSWindow.Level.statusBar.rawValue)
        #expect(NSWindow.Level.modalPanel.rawValue < NSWindow.Level.statusBar.rawValue)
    }
    @MainActor @Test func sheetsUseTheActualPresenterOrderingBand() {
        let parent = NotchPresenter.windowLevel
        #expect(parent == .statusBar)
        #expect(NoteDialogPresentation.sheetLevel(parent: parent) == parent)
        #expect(NoteDialogPresentation.sheetLevel(parent: .floating) == .floating)
    }
}
