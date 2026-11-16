import AppKit
import SwiftUI
import Testing
@testable import Scribbit

@MainActor
struct NoteFooterTests {
    @Test func disclosureRemainsCenteredAndOperableInBothStates() throws {
        for expanded in [false, true] {
            var toggles = 0
            let host = NSHostingView(rootView: NoteFooter(isExpanded: expanded) { toggles += 1 })
            host.frame = NSRect(x: 0, y: 0, width: 340, height: 28)
            host.layoutSubtreeIfNeeded()
            let button = try #require(disclosure(in: host))
            let frame = host.convert(button.bounds, from: button)
            #expect(abs(frame.midX - host.bounds.midX) < 0.5)
            #expect(abs(frame.height - 20) < 0.5)
            #expect(abs(host.fittingSize.height - 28) < 0.5)
            #expect(button.accessibilityLabel() == (expanded
                ? "Hide note information and controls"
                : "Show note information and controls"))
            #expect(button.isEnabled)
            button.performClick(nil)
            #expect(toggles == 1)
            #expect(host.window == nil)
        }
    }

    @Test func editorHasEightPointClearanceAboveFooterInBothStates() throws {
        for expanded in [false, true] {
            let host = NSHostingView(rootView: VStack(spacing: 0) {
                NativeEditor(text: .constant("A disposable layout fixture."), selection: nil)
                NoteFooter(isExpanded: expanded) {}
            })
            host.frame = NSRect(x: 0, y: 0, width: 620, height: 300)
            host.layoutSubtreeIfNeeded()
            let button = try #require(disclosure(in: host))
            let editor = try #require(scrollView(in: host))
            let buttonFrame = host.convert(button.bounds, from: button)
            let editorFrame = host.convert(editor.bounds, from: editor)
            let clearance = host.isFlipped
                ? buttonFrame.minY - editorFrame.maxY
                : editorFrame.minY - buttonFrame.maxY
            // Windowless SwiftUI/AppKit hosting can snap native control edges
            // by one point. Missing padding still fails by eight points.
            #expect(abs(clearance - 8) <= 1,
                    "expanded=\(expanded), flipped=\(host.isFlipped), button=\(buttonFrame), editor=\(editorFrame)")
            #expect(abs(editorFrame.height - 272) < 0.5)
            #expect(host.window == nil)
        }
    }

    private func disclosure(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.identifier?.rawValue == "toggleNoteInformation" { return button }
        return view.subviews.lazy.compactMap { disclosure(in: $0) }.first
    }

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
}
