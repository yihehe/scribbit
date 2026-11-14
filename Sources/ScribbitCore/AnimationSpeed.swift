import Foundation

/// Speed is a playback rate: 2x takes half as long, without changing the spring.
public enum AnimationSpeed {
    public static let range = 0.5...2.0
    public static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(range.upperBound, max(range.lowerBound, value))
    }
    public static func label(_ rate: Double) -> String { String(format: "%g×", normalized(rate)) }
    public static func duration(_ seconds: Double, rate: Double) -> Double {
        seconds / normalized(rate)
    }
}
