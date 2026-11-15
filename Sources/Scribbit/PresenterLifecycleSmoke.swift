import AppKit
import ScribbitCore

extension SmokeTestDelegate {
    /// Exercises real cancellation ordering, independently of note content/I/O.
    @MainActor
    func verifyPresenterLifecycle() async throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else {
                throw NSError(domain: "PresenterLifecycle", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        func wait(_ condition: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while !condition() {
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    throw NSError(domain: "PresenterLifecycle", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Transition did not start"])
                }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        // A stock panel and plain NSView prove there is no note/editor coupling.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        defer { panel.orderOut(nil) }
        let presenter = NotchPresenter(panel: panel, content: NSView())
        let geometry = NotchGeometry(screen: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     cameraWidth: 184, topInset: 32)
        presenter.configure(geometry)
        presenter.animationSpeed = 0.5

        let firstOpening = Task { await presenter.reveal(takeFocus: false, reduceMotion: false) }
        try await wait { presenter.phase == .expanding }
        presenter.configure(geometry) // Cancels A, with A's caller still awaiting.
        var staleOpeningWasHarmless = false
        let openingObserver = Task {
            await firstOpening.value
            staleOpeningWasHarmless = presenter.phase == .expanding && presenter.hasAnimations
        }
        // Start B before yielding: resuming A must not mark B as already expanded.
        await presenter.reveal(takeFocus: false, reduceMotion: false)
        await openingObserver.value
        try check(staleOpeningWasHarmless, "Superseded reveal changed the replacement transition's phase")
        try check(presenter.phase == .expanded && !presenter.hasAnimations, "Replacement reveal did not settle")

        let firstClosing = Task { await presenter.dismiss(reduceMotion: false) }
        try await wait { presenter.phase == .collapsing }
        var replacementWaiterStarted = false
        var replacementWaiterSawSettledState = false
        let replacementWaiter = Task {
            replacementWaiterStarted = true
            await presenter.waitUntilSettled()
            replacementWaiterSawSettledState = !presenter.isTransitioning && !presenter.hasAnimations
        }
        try await wait { replacementWaiterStarted }
        presenter.configure(geometry)
        var staleClosingWasHarmless = false
        let closingObserver = Task {
            await firstClosing.value
            staleClosingWasHarmless = panel.isVisible && presenter.phase == .expanding
        }
        // A cancelled close must not hide the panel when its caller resumes in B.
        await presenter.reveal(takeFocus: false, reduceMotion: false)
        await closingObserver.value
        await replacementWaiter.value
        try check(staleClosingWasHarmless, "Superseded dismiss hid a replacement reveal")
        try check(replacementWaiterSawSettledState, "A waiter returned before the replacement transition settled")
        try check(panel.isVisible && presenter.phase == .expanded, "Replacement panel was not visible")

        let closing = Task { await presenter.dismiss(reduceMotion: true) }
        try await wait { presenter.phase == .collapsing }
        let waiters = (0..<3).map { _ in Task { await presenter.waitUntilSettled() } }
        await closing.value
        for waiter in waiters { await waiter.value }
        await presenter.waitUntilSettled() // Idle waits must also complete.
        try check(presenter.phase == .hidden && !panel.isVisible && !presenter.hasAnimations,
                  "Transition waiters did not settle cleanly")
        print("PRESENTER_LIFECYCLE_SMOKE_PASS: generic panel/content, superseded reveal/close, replacement-aware/multiple waiters, idle wait")
    }
}
