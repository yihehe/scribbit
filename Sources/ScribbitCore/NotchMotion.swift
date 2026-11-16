import Foundation
import CoreGraphics

/// Damped oscillator sampled for Core Animation. Scribbit's motion settings
/// and timing behavior are documented in Docs/NOTCH-UX.md.
public enum NotchMotion {
    public static let exitDelay = 0.18
    public static let revealDuration = 0.45
    public static let departureDuration = 0.16
    public static let arrivalScale = 0.86
    public static let margin: CGFloat = 12

    public struct Axis {
        public let duration: Double
        public let damping: Double
        public init(start: CGFloat, end: CGFloat, horizontal: Bool) {
            let growing = end > start
            duration = growing ? (horizontal ? 0.44 : 0.38) : (horizontal ? 0.30 : 0.26)
            let defaultDamping = growing ? (horizontal ? 0.75 : 0.78) : 1.0
            let distance = Double(abs(end - start))
            // Convert the maximum overshoot fraction into a damping ratio.
            let logLimit = log(min(1, 12 / max(12, distance)))
            let minimumDamping = -logLimit / sqrt(.pi * .pi + logLimit * logLimit)
            damping = max(defaultDamping, minimumDamping)
        }
        public func fraction(at seconds: Double) -> Double {
            guard seconds > 0 else { return 0 }
            let frequency = 2 * Double.pi / duration
            let envelope = exp(-frequency * damping * seconds)
            guard damping < 1 else { return 1 - envelope * (1 + frequency * seconds) }
            let oscillation = frequency * sqrt(1 - damping * damping)
            return 1 - envelope * (cos(oscillation * seconds) + frequency * damping / oscillation * sin(oscillation * seconds))
        }
    }

    public struct Plan {
        public let sizes: [CGSize]
        public let keyTimes: [Double]
        public let duration: Double
        public init(from start: CGSize, to end: CGSize) {
            let x = Axis(start: start.width, end: end.width, horizontal: true)
            let y = Axis(start: start.height, end: end.height, horizontal: false)
            func sample(_ time: Double) -> CGSize {
                CGSize(width: start.width + (end.width - start.width) * x.fraction(at: time),
                       height: start.height + (end.height - start.height) * y.fraction(at: time))
            }
            // Last excursion outside half a point; append an exact final target.
            let step = 1.0 / 240.0
            var lastUnsettled = step
            for index in 1...480 {
                let value = sample(Double(index) * step)
                if abs(value.width - end.width) > 0.5 || abs(value.height - end.height) > 0.5 {
                    lastUnsettled = Double(index + 1) * step
                }
            }
            let total = max(step, lastUnsettled)
            duration = total
            let count = max(1, Int(ceil(total * 120)))
            keyTimes = (0...count).map { Double($0) / Double(count) }
            sizes = keyTimes.map { $0 == 1 ? end : sample($0 * total) }
        }
    }
}

/// Circular-arc silhouette in an ordinary AppKit, bottom-left coordinate space.
/// The top edge is invariant: opening never drifts away from the camera.
public enum NotchContour {
    public static func path(size: CGSize, in canvas: CGSize) -> CGPath {
        let width = max(1, min(canvas.width, size.width))
        let height = max(1, min(canvas.height, size.height))
        let wing = min(14, height * 0.19, width / 4)
        let radius = min(28, height * 0.34, height / 2, (width - wing * 2) / 2)
        let left = (canvas.width - width) / 2
        let right = left + width
        let top = canvas.height
        let bottom = top - height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addArc(center: CGPoint(x: right, y: top - wing), radius: wing,
                    startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: right - wing, y: bottom + radius))
        path.addArc(center: CGPoint(x: right - wing - radius, y: bottom + radius), radius: radius,
                    startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: left + wing + radius, y: bottom))
        path.addArc(center: CGPoint(x: left + wing + radius, y: bottom + radius), radius: radius,
                    startAngle: -.pi / 2, endAngle: -.pi, clockwise: true)
        path.addLine(to: CGPoint(x: left + wing, y: top - wing))
        path.addArc(center: CGPoint(x: left, y: top - wing), radius: wing,
                    startAngle: 0, endAngle: .pi / 2, clockwise: false)
        path.closeSubpath()
        return path
    }
}

public enum NotchInteraction {
    public static func closesOnExit(openedByHover: Bool, pinned: Bool, inside: Bool,
                                    heldByUI: Bool, busy: Bool, dragging: Bool) -> Bool {
        openedByHover && !pinned && !inside && !heldByUI && !busy && !dragging
    }
}
