import Foundation

/// Entry dwell in seconds, independent of exit timing and animation playback.
public enum HoverDelay {
    public static let defaultValue = 0.10
    public static let range = 0.0...1.0
    public static let step = 0.05

    public static func normalized(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultValue }
        let bounded = min(range.upperBound, max(range.lowerBound, seconds))
        let stepped = (bounded / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }

    public static func label(_ seconds: Double) -> String {
        String(format: "%.0f ms", normalized(seconds) * 1_000)
    }
}
