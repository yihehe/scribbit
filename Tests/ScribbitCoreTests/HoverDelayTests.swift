import Testing
@testable import ScribbitCore

struct HoverDelayTests {
    @Test func defaultOpensSoonerAndLabelsUseMilliseconds() {
        #expect(HoverDelay.defaultValue == 0.1)
        #expect(HoverDelay.defaultValue < 0.25)
        #expect(HoverDelay.label(HoverDelay.defaultValue) == "100 ms")
        #expect(HoverDelay.label(HoverDelay.range.lowerBound) == "0 ms")
        #expect(HoverDelay.label(HoverDelay.range.upperBound) == "1000 ms")
    }

    @Test func zeroIsAnExplicitOptionWithoutChangingTheDefault() {
        #expect(HoverDelay.normalized(0) == 0)
        #expect(HoverDelay.label(0) == "0 ms")
        #expect(HoverDelay.defaultValue == 0.1)
    }

    @Test func nonfiniteValuesFallBackAndFiniteValuesClamp() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(HoverDelay.normalized(value) == HoverDelay.defaultValue)
            #expect(HoverDelay.label(value) == "100 ms")
        }
        #expect(HoverDelay.normalized(-1) == 0)
        #expect(HoverDelay.normalized(0) == 0)
        #expect(HoverDelay.normalized(Double.leastNonzeroMagnitude) == 0)
        #expect(HoverDelay.normalized(Double.greatestFiniteMagnitude) == 1)
        #expect(HoverDelay.normalized(10) == 1)
    }

    @Test func normalizedValuesUseFiftyMillisecondSteps() {
        #expect(HoverDelay.normalized(0.024) == 0)
        #expect(HoverDelay.normalized(0.026) == 0.05)
        #expect(abs(HoverDelay.normalized(0.124) - 0.10) < 0.000_001)
        #expect(abs(HoverDelay.normalized(0.126) - 0.15) < 0.000_001)
        for tick in 0...20 {
            let seconds = Double(tick) * HoverDelay.step
            let result = HoverDelay.normalized(seconds)
            #expect(abs(result - seconds) < 0.000_001)
            #expect(HoverDelay.range.contains(result))
            #expect(HoverDelay.normalized(result) == result)
        }
    }

    @Test func entryPreferenceDoesNotChangeOtherClocks() {
        #expect(NotchMotion.exitDelay == 0.18)
        #expect(NotchMotion.revealDuration == 0.45)
        #expect(NotchMotion.departureDuration == 0.16)
        #expect(AnimationSpeed.duration(0.44, rate: 2) == 0.22)
        #expect(HoverDelay.normalized(HoverDelay.defaultValue) == 0.1)
    }
}
