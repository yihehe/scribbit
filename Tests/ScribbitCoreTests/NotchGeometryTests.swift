import Foundation
import CoreGraphics
import Testing
@testable import ScribbitCore

final class NotchGeometryTests {
    @Test func testAttachedSurfaceAndContentStayBelowCamera() {
        let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), cameraWidth: 184, topInset: 32)
        expectEqual(g.trigger, CGRect(x: 658, y: 944, width: 196, height: 38))
        expectTrue(g.trigger.contains(CGPoint(x: 756, y: 947)))
        expectEqual(g.panelFrame().maxY, 982)
        expectEqual(g.screen.maxY - g.contentTop, 942)
        #expect(g.indicator.minX < g.trigger.minX)
    }
    @Test func testUnnotchedDisplayFallback() {
        let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), cameraWidth: 0, topInset: 0)
        expectEqual(g.trigger.size, CGSize(width: 120, height: 8))
        expectEqual(g.trigger.midX, 960)
        expectEqual(g.panelFrame().maxY, 1080)
        expectEqual(g.screen.maxY - g.contentTop, 1048)
    }
    @Test func testSecondaryDisplayWithNegativeOrigin() {
        let g = NotchGeometry(screen: CGRect(x: -1920, y: -100, width: 1920, height: 1080), cameraWidth: 0, topInset: 0)
        expectEqual(g.trigger.midX, -960)
        expectEqual(g.trigger.maxY, 980)
        expectTrue(g.screen.contains(g.panelFrame()))
    }
    @Test func testSmallScreenClampsPanel() {
        let g = NotchGeometry(screen: CGRect(x: 40, y: 50, width: 400, height: 300), cameraWidth: 100, topInset: 20)
        expectTrue(g.screen.contains(g.panelFrame()))
        expectEqual(g.panelFrame().width, 376)
    }
    @Test func testInvalidInsetsAreClamped() {
        let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1000, height: 600), cameraWidth: -10, topInset: -10)
        expectEqual(g.cameraWidth, 0)
        expectEqual(g.topInset, 0)
    }
    @Test func testDwellScheduledOnlyOncePerEntry() {
        var gate = HoverGate()
        expectFalse(gate.move(to: nil))
        expectTrue(gate.move(to: 0))
        expectFalse(gate.move(to: 0))
        expectTrue(gate.canOpen(0))
        expectFalse(gate.canOpen(1))
        expectFalse(gate.move(to: nil))
        expectFalse(gate.canOpen(0))
        expectTrue(gate.move(to: 0))
    }
    @Test func testClosingRequiresPointerExitBeforeReopening() {
        var gate = HoverGate()
        expectTrue(gate.move(to: 0))
        gate.suppressUntilExit()
        expectFalse(gate.canOpen(0))
        expectFalse(gate.move(to: 0))
        expectFalse(gate.move(to: 1))
        expectFalse(gate.move(to: nil))
        expectTrue(gate.move(to: 0))
    }
    @Test func testMovingToAnotherDisplayInvalidatesOldDwell() {
        var gate = HoverGate()
        expectTrue(gate.move(to: 0))
        expectTrue(gate.move(to: 1))
        expectFalse(gate.canOpen(0))
        expectTrue(gate.canOpen(1))
    }
    @Test func testLeftWingJoinsCutoutAndKeepsPencilClearOfCamera() {
        let g = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), cameraWidth: 184, topInset: 32)
        #expect(g.indicator.maxY == g.screen.maxY)
        #expect(g.indicator.maxX == g.screen.midX + g.collapsedSize.width / 2)
        #expect(g.indicatorIcon.maxX < g.screen.midX - g.cameraWidth / 2)
        #expect(g.indicatorContains(CGPoint(x: g.indicatorIcon.midX, y: g.indicatorIcon.midY)))
        #expect(g.indicatorContains(CGPoint(x: g.indicatorIcon.midX, y: g.screen.maxY)))
        #expect(!g.indicatorContains(CGPoint(x: g.indicator.minX + 0.1, y: g.indicator.maxY - 8)))
        #expect(g.restingSize(showsWing: true) == g.indicator.size)
        #expect(g.restingOffset(showsWing: true) == -18)
        #expect(g.restingSize(showsWing: false) == g.collapsedSize)
        #expect(g.restingOffset(showsWing: false) == 0)
    }
    @Test func testLeftWingOnUnnotchedNegativeOriginDisplay() {
        let g = NotchGeometry(screen: CGRect(x: -1920, y: -100, width: 1920, height: 1080), cameraWidth: 0, topInset: 0)
        #expect(g.screen.contains(g.indicator))
        #expect(g.indicator.height == 24)
        #expect(g.indicatorIcon.maxX < g.screen.midX)
    }

}
