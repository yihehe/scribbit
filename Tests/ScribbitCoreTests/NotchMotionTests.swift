import Foundation
import CoreGraphics
import Testing
@testable import ScribbitCore

struct NotchMotionTests {
    @Test func testAxisTimingsMatchInspectedProfile() {
        #expect(NotchMotion.Axis(start: 200, end: 660, horizontal: true).duration == 0.44)
        #expect(NotchMotion.Axis(start: 32, end: 512, horizontal: false).duration == 0.38)
        #expect(NotchMotion.Axis(start: 660, end: 200, horizontal: true).duration == 0.30)
        #expect(NotchMotion.Axis(start: 512, end: 32, horizontal: false).duration == 0.26)
        #expect(NotchMotion.hoverDelay == 0.25)
        #expect(NotchMotion.exitDelay == 0.18)
    }
    @Test func testExpansionOvershootsButNeverMoreThanTwelvePoints() {
        let start = CGSize(width: 196, height: 32), end = CGSize(width: 660, height: 512)
        let plan = NotchMotion.Plan(from: start, to: end)
        #expect(plan.sizes.first == start)
        #expect(plan.sizes.last == end)
        #expect(plan.sizes.contains { $0.width > end.width })
        #expect(plan.sizes.allSatisfy { $0.width <= end.width + 12.01 && $0.height <= end.height + 12.01 })
        #expect(plan.keyTimes.first == 0)
        #expect(plan.keyTimes.last == 1)
        #expect(plan.keyTimes.count == plan.sizes.count)
        #expect(plan.duration > 0 && plan.duration < 2)
    }
    @Test func testCollapseIsMonotoneAndEndsExactlyAtNotch() {
        let end = CGSize(width: 196, height: 32)
        let plan = NotchMotion.Plan(from: CGSize(width: 660, height: 512), to: end)
        for pair in zip(plan.sizes, plan.sizes.dropFirst()) {
            #expect(pair.1.width <= pair.0.width)
            #expect(pair.1.height <= pair.0.height)
        }
        #expect(plan.sizes.last == end)
    }
    @Test func testStationaryAndLargeTravelRemainFinite() {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 10000, height: 10000)] {
            let plan = NotchMotion.Plan(from: size, to: size)
            #expect(plan.sizes.allSatisfy { $0 == size })
        }
        let axis = NotchMotion.Axis(start: 1, end: 10000, horizontal: true)
        #expect(axis.damping > 0.75)
        #expect(axis.fraction(at: 0) == 0)
        #expect(abs(axis.fraction(at: 2) - 1) < 0.001)
    }
    @Test func testContourIsTopAttachedAndHasTransparentShoulders() {
        let canvas = CGSize(width: 684, height: 524)
        let path = NotchContour.path(size: CGSize(width: 660, height: 512), in: canvas)
        #expect(path.boundingBoxOfPath == CGRect(x: 12, y: 12, width: 660, height: 512))
        #expect(path.contains(CGPoint(x: 342, y: 500)))
        #expect(path.contains(CGPoint(x: 342, y: 20)))
        #expect(!path.contains(CGPoint(x: 13, y: 510)))
        #expect(!path.contains(CGPoint(x: 32, y: 13)))
    }
    @Test func testEverySpringFrameFitsReservationAndKeepsTopFixed() {
        let canvas = CGSize(width: 684, height: 524)
        let plan = NotchMotion.Plan(from: CGSize(width: 196, height: 32), to: CGSize(width: 660, height: 512))
        for size in plan.sizes {
            let box = NotchContour.path(size: size, in: canvas).boundingBoxOfPath
            #expect(abs(box.maxY - canvas.height) < 0.001)
            #expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= canvas.width)
        }
    }
    @Test func testExactScreenTopIsAnEligibleHoverTarget() {
        let geometry = NotchGeometry(screen: CGRect(x: -1000, y: 40, width: 1000, height: 800), cameraWidth: 180, topInset: 32)
        #expect(geometry.triggerContains(CGPoint(x: -500, y: 840)))
        #expect(!geometry.triggerContains(CGPoint(x: -500, y: 841)))
    }
    @Test func testHoverExitHonorsEveryWorkingSurfaceHold() {
        #expect(NotchInteraction.closesOnExit(openedByHover: true, pinned: false, inside: false, heldByUI: false, busy: false, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: false, pinned: false, inside: false, heldByUI: false, busy: false, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: true, pinned: true, inside: false, heldByUI: false, busy: false, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: true, pinned: false, inside: true, heldByUI: false, busy: false, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: true, pinned: false, inside: false, heldByUI: true, busy: false, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: true, pinned: false, inside: false, heldByUI: false, busy: true, dragging: false))
        #expect(!NotchInteraction.closesOnExit(openedByHover: true, pinned: false, inside: false, heldByUI: false, busy: false, dragging: true))
    }

}
