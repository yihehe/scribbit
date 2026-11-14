import AppKit

/// GUI-test artifact rendering. Layer-backed cacheDisplay omits the backing mask,
/// so apply the same model contour explicitly for transparent-corner PNGs.
@MainActor
enum NativeSnapshot {
    static func write(view: NSView, contour: CGPath?, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let source = bitmap.cgImage,
              let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        context.scaleBy(x: CGFloat(bitmap.pixelsWide) / view.bounds.width,
                        y: CGFloat(bitmap.pixelsHigh) / view.bounds.height)
        if let contour { context.addPath(contour); context.clip() }
        context.draw(source, in: view.bounds)
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
