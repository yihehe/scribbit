import CoreGraphics
import Foundation

public struct NotchGeometry: Equatable {
    public let screen: CGRect
    public let cameraWidth: CGFloat
    public let topInset: CGFloat
    public init(screen: CGRect, cameraWidth: CGFloat, topInset: CGFloat) {
        self.screen = screen
        self.cameraWidth = max(0, cameraWidth)
        self.topInset = max(0, topInset)
    }
    /// On unnotched displays, use a small top-center hot zone. Include six points
    /// below a physical notch so the trigger is reachable without entering the camera.
    public var trigger: CGRect {
        let width = min(screen.width, max(120, cameraWidth + 12))
        let height = max(8, topInset + 6)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
    public func triggerContains(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: trigger.size).contains(CGPoint(x: point.x - trigger.minX, y: trigger.maxY - point.y))
    }
    /// One black, asymmetric resting surface: a left wing joined to the cutout.
    public var indicator: CGRect {
        let wing = min(36, max(0, (screen.width - collapsedSize.width - 24) / 2))
        let height = max(24, topInset)
        return CGRect(x: screen.midX - collapsedSize.width / 2 - wing,
                      y: screen.maxY - height, width: collapsedSize.width + wing, height: height)
    }
    public var indicatorIcon: CGRect {
        let wing = indicator.width - collapsedSize.width
        return CGRect(x: indicator.minX + wing / 2 - 7, y: indicator.midY - 7, width: 14, height: 14)
    }
    public func indicatorContains(_ point: CGPoint) -> Bool {
        if point.y == indicator.maxY, point.x >= indicator.minX, point.x < indicator.maxX { return true }
        let local = CGPoint(x: point.x - indicator.minX, y: point.y - indicator.minY)
        return NotchContour.path(size: indicator.size, in: indicator.size).contains(local)
    }
    public func restingSize(showsWing: Bool) -> CGSize { showsWing ? indicator.size : collapsedSize }
    public func restingOffset(showsWing: Bool) -> CGFloat { showsWing ? indicator.midX - screen.midX : 0 }
    public var contentTop: CGFloat { max(24, topInset) + 8 }
    public var collapsedSize: CGSize {
        CGSize(width: max(1, min(screen.width - 24, max(120, cameraWidth + 12))), height: max(8, topInset))
    }
    public var expandedSize: CGSize {
        CGSize(width: min(660, max(1, screen.width - 48)),
               height: min(460 + contentTop + 12, max(1, screen.height - 36)))
    }
    /// A pointer-only grace area around the open surface. This does not change
    /// the closed trigger, visible contour, native window, or click hit testing.
    public var hoverRetentionFrame: CGRect {
        let surface = CGRect(x: screen.midX - expandedSize.width / 2,
                             y: screen.maxY - expandedSize.height,
                             width: expandedSize.width, height: expandedSize.height)
        return surface.insetBy(dx: -48, dy: -24).intersection(screen)
    }
    public func hoverRetentionContains(_ point: CGPoint) -> Bool {
        let frame = hoverRetentionFrame
        // Include the physical screen's exact top edge like triggerContains.
        return !frame.isNull && point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
    /// Reserve the spring overshoot once, never resize the window on each frame.
    public func panelFrame() -> CGRect {
        let size = CGSize(width: expandedSize.width + 24, height: expandedSize.height + 12)
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// NSWindowDelegate sheet attachment uses window coordinates. Keep its top
    /// below the same camera-safe boundary as note content, on any display.
    public func sheetAttachmentRect(in windowFrame: CGRect, proposed: CGRect) -> CGRect {
        let safeY = screen.maxY - contentTop - windowFrame.minY
        return CGRect(x: proposed.minX, y: max(0, min(proposed.minY, safeY)),
                      width: proposed.width, height: 0)
    }

}

/// One dwell per entry; closing while still over the notch cannot reopen it.
public struct HoverGate {
    public private(set) var target: Int?
    private var suppressed = false
    public init() {}
    public mutating func move(to next: Int?) -> Bool {
        if next == nil { target = nil; suppressed = false; return false }
        guard !suppressed, next != target else { return false }
        target = next
        return true
    }
    public mutating func suppressUntilExit() { suppressed = true; target = nil }
    public func canOpen(_ candidate: Int) -> Bool { !suppressed && target == candidate }
}
