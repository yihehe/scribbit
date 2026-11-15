import AppKit
import ImageIO
import UniformTypeIdentifiers
import ScribbitCore

/// Fixture-only illustrative GIF generated from the same motion profile. Not a
/// screen recording or evidence of OS event delivery on physical notch hardware.
@MainActor
enum MotionPreview {
    static func export(presenter: NotchPresenter, sourceURL: URL, destination: URL) throws {
        guard let geometry = presenter.geometry,
              let source = NSImage(contentsOf: sourceURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileReadUnknown)
        }
        let start = geometry.collapsedSize, end = geometry.expandedSize
        let opening = NotchMotion.Plan(from: start, to: end)
        let closing = NotchMotion.Plan(from: end, to: start)
        let openingTime = max(opening.duration, NotchMotion.revealDuration)
        let closeStart = openingTime + 0.4
        let length = closeStart + closing.duration + 0.3
        let frames = Int(ceil(length * 30))
        guard let gif = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        func eased(_ fraction: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
            let x = min(1, max(0, fraction))
            func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1-t) * (1-t) * t * a + 3 * (1-t) * t * t * b + t * t * t
            }
            var lower = 0.0, upper = 1.0
            for _ in 0..<24 {
                let middle = (lower + upper) / 2
                if bezier(middle, x1, x2) < x { lower = middle } else { upper = middle }
            }
            return bezier((lower + upper) / 2, y1, y2)
        }
        let pixelWidth = Int(presenter.canvas.bounds.width.rounded(.up))
        let pixelHeight = Int(presenter.canvas.bounds.height.rounded(.up))
        for index in 0..<frames {
            let time = Double(index) / 30
            let shrinking = time >= closeStart
            let elapsed = shrinking ? time - closeStart : time
            let plan = shrinking ? closing : opening
            let a = shrinking ? end : start, b = shrinking ? start : end
            let size = elapsed >= plan.duration ? b : CGSize(
                width: a.width + (b.width-a.width) * NotchMotion.Axis(start: a.width, end: b.width, horizontal: true).fraction(at: elapsed),
                height: a.height + (b.height-a.height) * NotchMotion.Axis(start: a.height, end: b.height, horizontal: false).fraction(at: elapsed))
            let alpha = shrinking
                ? 1 - eased(elapsed / NotchMotion.departureDuration, x1: 0.42, y1: 0, x2: 1, y2: 1)
                : eased((elapsed / NotchMotion.revealDuration - 0.35) / 0.65, x1: 0, y1: 0, x2: 0.58, y2: 1)
            let scale = shrinking ? 1 : NotchMotion.arrivalScale + (1-NotchMotion.arrivalScale)
                * eased(elapsed / NotchMotion.revealDuration, x1: 0.22, y1: 1, x2: 0.36, y2: 1)
            guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            let bounds = presenter.canvas.bounds
            context.scaleBy(x: CGFloat(pixelWidth)/bounds.width, y: CGFloat(pixelHeight)/bounds.height)
            context.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor); context.fill(bounds)
            context.addPath(NotchContour.path(size: size, in: bounds.size)); context.clip()
            context.setFillColor(NSColor.black.cgColor); context.fill(bounds)
            let anchor = CGPoint(x: bounds.midX, y: bounds.maxY - geometry.contentTop)
            context.translateBy(x: anchor.x, y: anchor.y); context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -anchor.x, y: -anchor.y)
            context.setAlpha(alpha); context.draw(source, in: bounds)
            guard let frame = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0/30]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
    }
}
