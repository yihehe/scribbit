import AppKit
import QuartzCore
import ScribbitCore

/// A left activity wing, joined to the physical cutout with one black contour.
/// The window ignores mouse clicks; the existing hover monitor owns discovery.
@MainActor
final class RestingNotchView: NSView {
    private let contour: CGPath
    init(geometry: NotchGeometry) {
        let size = geometry.indicator.size
        contour = NotchContour.path(size: size, in: size)
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = contour
        layer?.mask = mask
        let icon = NSImageView(frame: geometry.indicatorIcon.offsetBy(dx: -geometry.indicator.minX, dy: -geometry.indicator.minY))
        icon.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Hover to open Scribbit")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        addSubview(icon)
    }
    required init?(coder: NSCoder) { nil }
    func capture(to url: URL) throws { try NativeSnapshot.write(view: self, contour: contour, to: url) }
}
