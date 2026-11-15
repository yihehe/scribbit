import Testing
@testable import ScribbitCore

struct AnimationSpeedTests {
    @Test func testPlaybackRatesScaleTimeNotMotionValues() {
        #expect(AnimationSpeed.label(1.25) == "1.25×")
        #expect(AnimationSpeed.label(1.75) == "1.75×")
        #expect(AnimationSpeed.duration(0.44, rate: 2) == 0.22)
        #expect(AnimationSpeed.duration(0.44, rate: 0.5) == 0.88)
        #expect(AnimationSpeed.duration(0.45, rate: 1) == 0.45)
    }
    @Test func testUntrustedRatesCannotCreateInvalidAnimationDurations() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(AnimationSpeed.normalized(value) == 1)
            #expect(AnimationSpeed.duration(0.3, rate: value) == 0.3)
        }
        #expect(AnimationSpeed.normalized(0) == 0.5)
        #expect(AnimationSpeed.normalized(10) == 2)
    }
}
