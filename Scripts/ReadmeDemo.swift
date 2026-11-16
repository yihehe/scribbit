import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Documentation-only offscreen fixture. No NSApplication, NSWindow, source
/// note, preferences, event monitor, network request or desktop capture.
@main
struct ReadmeDemo {
    static let canvas = CGSize(width: 800, height: 560)
    static let fps = 20.0
    static let sample = "A little space for a quick thought.\n\nWrite down the idea.\nKeep the useful bit.\nGet back to work."
    static let geometry = NotchGeometry(
        screen: CGRect(origin: .zero, size: canvas), cameraWidth: 184, topInset: 32)
    static var frog: CGImage!

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fputs("Usage: export-demo GIF_PATH PREVIEW_PNG_PATH FROG_PNG_PATH\n", stderr)
            exit(64)
        }
        guard let frogSource = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: CommandLine.arguments[3]) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(frogSource, 0, nil),
              image.width == 28, image.height == 28 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        frog = image
        let destination = URL(fileURLWithPath: CommandLine.arguments[1])
        let preview = URL(fileURLWithPath: CommandLine.arguments[2])
        // Demonstrate the existing optional resting indicator enabled.
        let start = geometry.restingSize(showsWing: true)
        let end = geometry.expandedSize
        let opening = NotchMotion.Plan(from: start, to: end)
        let closing = NotchMotion.Plan(from: end, to: start)
        let openStart = 1.05 + HoverDelay.defaultValue // Rest, approach, configured default dwell.
        let openEnd = openStart + max(opening.duration, NotchMotion.revealDuration)
        let typingStart = openEnd + 0.28
        let typingEnd = typingStart + Double(sample.count) / 42
        let exitStart = typingEnd + 0.85
        let closeStart = exitStart + 0.35 + NotchMotion.exitDelay
        let duration = closeStart + closing.duration + 0.8
        let count = Int(ceil(duration * fps))
        guard let gif = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(gif, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        var wrotePreview = false
        for index in 0..<count {
            let time = Double(index) / fps
            let shrinking = time >= closeStart
            let elapsed = shrinking ? time - closeStart : time - openStart
            let a = shrinking ? end : start
            let b = shrinking ? start : end
            let plan = shrinking ? closing : opening
            let size: CGSize
            if elapsed <= 0 { size = a }
            else if elapsed >= plan.duration { size = b }
            else {
                size = CGSize(
                    width: a.width + (b.width - a.width) * NotchMotion.Axis(
                        start: a.width, end: b.width, horizontal: true).fraction(at: elapsed),
                    height: a.height + (b.height - a.height) * NotchMotion.Axis(
                        start: a.height, end: b.height, horizontal: false).fraction(at: elapsed))
            }
            let opacity = shrinking
                ? 1 - ease(elapsed / NotchMotion.departureDuration, 0.42, 0, 1, 1)
                : ease((elapsed / NotchMotion.revealDuration - 0.35) / 0.65, 0, 0, 0.58, 1)
            let scale = shrinking ? 1 : NotchMotion.arrivalScale + (1 - NotchMotion.arrivalScale)
                * ease(elapsed / NotchMotion.revealDuration, 0.22, 1, 0.36, 1)
            let text = String(sample.prefix(max(0, min(sample.count,
                Int((time - typingStart) * 42)))))
            let showCaret = time >= typingStart && time < exitStart
                && (time < typingEnd || Int(time * 2) % 2 == 0)
            let progress = elapsed <= 0 ? 0 : elapsed >= plan.duration ? 1
                : NotchMotion.Axis(start: a.width, end: b.width, horizontal: true).fraction(at: elapsed)
            let restingOffset = geometry.restingOffset(showsWing: true)
            let offset = shrinking ? restingOffset * progress : restingOffset * (1 - progress)
            // Production hides the separate resting indicator before expansion,
            // then restores it once collapse completes.
            let showRestingIcon = shrinking ? elapsed >= plan.duration : elapsed < 0
            let frame = try render(size: size, offset: offset, showRestingIcon: showRestingIcon,
                text: text, opacity: opacity, scale: scale,
                pointer: pointer(time, openEnd: openEnd, typingStart: typingStart,
                                 exitStart: exitStart), showCaret: showCaret)
            CGImageDestinationAddImage(gif, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]
            ] as CFDictionary)
            if !wrotePreview && time >= typingEnd {
                try writePNG(frame, to: preview)
                wrotePreview = true
            }
        }
        guard CGImageDestinationFinalize(gif) else { throw CocoaError(.fileWriteUnknown) }
        guard let source = CGImageSourceCreateWithURL(destination as CFURL, nil),
              CGImageSourceGetCount(source) == count,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil),
              first.width == Int(canvas.width), first.height == Int(canvas.height),
              (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) < 4 * 1_024 * 1_024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        guard (gifProperties?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for index in 0..<count {
            let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let timing = frame?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            guard let delay = timing?[kCGImagePropertyGIFDelayTime] as? NSNumber,
                  abs(delay.doubleValue - 1 / fps) < 0.001 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        print("README_DEMO_PASS: \(count) frames, \(Int(canvas.width))×\(Int(canvas.height)), \(String(format: "%.2f", Double(count) / fps)) s, \((try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)) bytes")
    }

    static func render(size: CGSize, offset: CGFloat, showRestingIcon: Bool,
                       text: String, opacity: Double, scale: Double,
                       pointer: CGPoint?, showCaret: Bool) throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bounds = CGRect(origin: .zero, size: canvas)
        context.setFillColor(CGColor(red: 0.86, green: 0.89, blue: 0.87, alpha: 1))
        context.fill(bounds)
        draw("Hover. Write. Back to work.", at: CGPoint(x: 400, y: 18),
             size: 15, color: CGColor(gray: 0.27, alpha: 1), centered: true, in: context)
        context.saveGState()
        var translation = CGAffineTransform(translationX: offset, y: 0)
        let path = NotchContour.path(size: size, in: canvas)
        context.addPath(path.copy(using: &translation) ?? path)
        context.clip()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        if showRestingIcon {
            context.saveGState()
            context.setAlpha(0.85)
            context.draw(frog, in: geometry.indicatorIcon)
            context.restoreGState()
        }
        let anchor = CGPoint(x: canvas.width / 2, y: canvas.height - geometry.contentTop)
        context.translateBy(x: anchor.x, y: anchor.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -anchor.x, y: -anchor.y)
        context.setAlpha(opacity)
        let content = CGRect(
            x: (canvas.width - geometry.expandedSize.width + 40) / 2,
            y: canvas.height - geometry.expandedSize.height + 12,
            width: geometry.expandedSize.width - 40,
            height: geometry.expandedSize.height - geometry.contentTop - 12)
        context.setFillColor(CGColor(gray: 0.035, alpha: 1))
        context.fill(content)
        let lines = text.components(separatedBy: "\n")
        let x = content.minX + 16
        let top = content.maxY - 30
        for (index, line) in lines.enumerated() {
            draw(line, at: CGPoint(x: x, y: top - CGFloat(index) * 19),
                 size: 14, color: CGColor(gray: 0.91, alpha: 1), monospaced: true, in: context)
        }
        if showCaret {
            let width = textWidth(lines.last ?? "", size: 14, monospaced: true)
            context.setFillColor(CGColor(gray: 0.91, alpha: 1))
            context.fill(CGRect(x: x + width + 1, y: top - CGFloat(lines.count - 1) * 19 - 3,
                                width: 1, height: 16))
        }
        context.setStrokeColor(CGColor(gray: 0.58, alpha: 1))
        context.setLineWidth(1.4)
        context.move(to: CGPoint(x: content.midX - 4, y: content.minY + 8))
        context.addLine(to: CGPoint(x: content.midX, y: content.minY + 12))
        context.addLine(to: CGPoint(x: content.midX + 4, y: content.minY + 8))
        context.strokePath()
        // Same 14-point asset, 5-point spacing, 11-point medium wordmark and
        // 16-point inset as NoteFooter. Identity only, not another command.
        context.saveGState()
        context.setAlpha(opacity * 0.58)
        context.draw(frog, in: CGRect(x: content.minX + 16, y: content.minY + 3,
                                     width: 14, height: 14))
        context.restoreGState()
        draw("Scribbit", at: CGPoint(x: content.minX + 35, y: content.minY + 6),
             size: 11, color: CGColor(gray: 0.58, alpha: 1), in: context)
        context.restoreGState()
        if let pointer { drawPointer(at: pointer, in: context) }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    static func pointer(_ time: Double, openEnd: Double, typingStart: Double,
                        exitStart: Double) -> CGPoint? {
        let outside = CGPoint(x: 710, y: 160)
        let trigger = CGPoint(x: 400, y: 523)
        if time < 0.6 { return outside }
        if time < 1.05 { return interpolate(outside, trigger, ease((time - 0.6) / 0.45, 0.42, 0, 0.58, 1)) }
        if time < openEnd { return trigger }
        if time < typingStart { return interpolate(trigger, CGPoint(x: 190, y: 470), (time - openEnd) / 0.28) }
        if time < exitStart { return nil }
        if time < exitStart + 0.35 {
            return interpolate(CGPoint(x: 190, y: 470), outside, ease((time - exitStart) / 0.35, 0.42, 0, 0.58, 1))
        }
        return outside
    }

    static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func drawPointer(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLines(between: [CGPoint(x: 0, y: -19), CGPoint(x: 5, y: -14),
            CGPoint(x: 9, y: -23), CGPoint(x: 12, y: -22), CGPoint(x: 8, y: -13),
            CGPoint(x: 15, y: -13)])
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }

    static func line(_ text: String, size: CGFloat, monospaced: Bool) -> CTLine {
        let font = monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]))
    }

    static func textWidth(_ text: String, size: CGFloat, monospaced: Bool) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, size: size, monospaced: monospaced), nil, nil, nil))
    }

    static func draw(_ text: String, at point: CGPoint, size: CGFloat, color: CGColor,
                     centered: Bool = false, monospaced: Bool = false, in context: CGContext) {
        context.saveGState()
        context.setFillColor(color)
        context.textPosition = CGPoint(x: centered ? point.x - textWidth(text, size: size, monospaced: monospaced) / 2 : point.x,
                                       y: point.y)
        CTLineDraw(line(text, size: size, monospaced: monospaced), context)
        context.restoreGState()
    }

    // Same content easing controls as the production presenter/fixture exporter.
    static func ease(_ fraction: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let x = min(1, max(0, fraction))
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        var lower = 0.0, upper = 1.0
        for _ in 0..<24 {
            let middle = (lower + upper) / 2
            if bezier(middle, x1, x2) < x { lower = middle } else { upper = middle }
        }
        return bezier((lower + upper) / 2, y1, y2)
    }

    static func writePNG(_ image: CGImage, to destination: URL) throws {
        guard let png = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(png, image, nil)
        guard CGImageDestinationFinalize(png) else { throw CocoaError(.fileWriteUnknown) }
    }
}
