import AppKit
import QuartzCore
import ScribbitCore

@MainActor
final class NotchPresenter {
    static let windowLevel: NSWindow.Level = .statusBar
    enum Phase { case hidden, expanding, expanded, collapsing }
    private(set) var phase: Phase = .hidden
    let panel: NSPanel
    let canvas = NSView()
    let content: NSView
    private let silhouette = CAShapeLayer()
    private(set) var geometry: NotchGeometry?
    private var transitionTask: Task<Void, Never>?
    private var generation = 0
    var animationSpeed = 1.0
    var showsRestingWing = false
    var isTransitioning: Bool { phase == .expanding || phase == .collapsing }

    /// The caller supplies window/focus policy; presentation has no note dependency.
    init(panel: NSPanel, content: NSView) {
        self.panel = panel
        self.content = content
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.black.cgColor
        canvas.layer?.mask = silhouette
        content.wantsLayer = true
        canvas.addSubview(content)
        panel.contentView = canvas
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        // The attached silhouette must cover the menu bar rather than sit under it.
        panel.level = Self.windowLevel
    }

    func configure(_ geometry: NotchGeometry) {
        let wasClosing = phase == .collapsing
        let wasVisible = phase != .hidden && !wasClosing
        settlePending()
        self.geometry = geometry
        panel.setFrame(geometry.panelFrame(), display: false)
        canvas.frame = CGRect(origin: .zero, size: panel.frame.size)
        let surface = geometry.expandedSize
        content.frame = CGRect(x: (canvas.bounds.width - surface.width + 40) / 2,
                               y: canvas.bounds.height - surface.height + 12,
                               width: max(1, surface.width - 40),
                               height: max(1, surface.height - geometry.contentTop - 12))
        content.layoutSubtreeIfNeeded()
        withoutActions {
            silhouette.frame = canvas.bounds
            silhouette.path = contour(wasVisible ? surface : geometry.restingSize(showsWing: showsRestingWing),
                                      offset: wasVisible ? 0 : geometry.restingOffset(showsWing: showsRestingWing))
            content.layer?.opacity = wasVisible ? 1 : 0
            content.layer?.transform = CATransform3DIdentity
        }
        phase = wasVisible ? .expanded : .hidden
    }

    func reveal(takeFocus: Bool, reduceMotion: Bool? = nil) async {
        guard let geometry else { return }
        settlePending()
        phase = .expanding
        panel.ignoresMouseEvents = false
        if takeFocus { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        await transition(from: geometry.restingSize(showsWing: showsRestingWing), to: geometry.expandedSize,
                         startOffset: geometry.restingOffset(showsWing: showsRestingWing), endOffset: 0, opening: true, reduceMotion: reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func dismiss(reduceMotion: Bool? = nil) async {
        guard let geometry else { panel.orderOut(nil); return }
        settlePending()
        phase = .collapsing
        panel.ignoresMouseEvents = true
        await transition(from: geometry.expandedSize, to: geometry.restingSize(showsWing: showsRestingWing),
                         startOffset: 0, endOffset: geometry.restingOffset(showsWing: showsRestingWing), opening: false, reduceMotion: reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func contour(_ size: CGSize, offset: CGFloat = 0) -> CGPath {
        let path = NotchContour.path(size: size, in: canvas.bounds.size)
        var transform = CGAffineTransform(translationX: offset, y: 0)
        return path.copy(using: &transform) ?? path
    }
    private func withoutActions(_ action: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        action()
        CATransaction.commit()
    }
    func waitUntilSettled() async {
        // Recheck after cancellation: a replacement may have started meanwhile.
        while let current = transitionTask { await current.value }
    }
    private func settlePending() {
        generation += 1
        transitionTask?.cancel()
        transitionTask = nil
        finishTransition()
    }
    private func finishTransition() {
        // Phase and visibility have one owner. Resuming an old reveal/dismiss
        // caller must never mutate a newer transition after its await.
        silhouette.removeAllAnimations()
        content.layer?.removeAllAnimations()
        if phase == .expanding { phase = .expanded }
        if phase == .collapsing {
            phase = .hidden
            panel.orderOut(nil)
            panel.ignoresMouseEvents = false
        }
    }
    private func transition(from: CGSize, to: CGSize, startOffset: CGFloat, endOffset: CGFloat, opening: Bool, reduceMotion: Bool) async {
        let plan = NotchMotion.Plan(from: from, to: to)
        let timeScale = 1 / AnimationSpeed.normalized(animationSpeed)
        let duration = reduceMotion ? 0.14 : max(plan.duration, opening ? NotchMotion.revealDuration : NotchMotion.departureDuration) * timeScale
        let token = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        withoutActions {
            silhouette.path = contour(to, offset: endOffset)
            content.layer?.opacity = opening ? 1 : 0
            content.layer?.transform = CATransform3DIdentity
        }
        if !reduceMotion {
            let shape = CAKeyframeAnimation(keyPath: "path")
            let axis = NotchMotion.Axis(start: from.width, end: to.width, horizontal: true)
            shape.values = zip(plan.sizes, plan.keyTimes).map { size, fraction in
                let progress = fraction == 1 ? 1 : axis.fraction(at: fraction * plan.duration)
                return contour(size, offset: startOffset + (endOffset - startOffset) * progress)
            }
            shape.keyTimes = plan.keyTimes.map { NSNumber(value: $0) }
            shape.duration = plan.duration * timeScale
            shape.calculationMode = .linear
            silhouette.add(shape, forKey: "notch.shape")
            if opening, let layer = content.layer {
                let scale = NotchMotion.arrivalScale
                let anchor = CGPoint(x: layer.anchorPoint.x * content.bounds.width,
                                     y: layer.anchorPoint.y * content.bounds.height)
                let top = CGPoint(x: content.bounds.midX, y: layer.contentsAreFlipped() ? 0 : content.bounds.height)
                var small = CATransform3DMakeScale(scale, scale, 1)
                small.m41 = (top.x - anchor.x) * (1 - scale)
                small.m42 = (top.y - anchor.y) * (1 - scale)
                let growth = CABasicAnimation(keyPath: "transform")
                growth.fromValue = NSValue(caTransform3D: small)
                growth.toValue = NSValue(caTransform3D: CATransform3DIdentity)
                growth.duration = NotchMotion.revealDuration * timeScale
                growth.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                layer.add(growth, forKey: "notch.contentScale")
            }
        }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = opening ? [0, 0, 1] : [1, 0]
        opacity.keyTimes = opening ? [0, reduceMotion ? 0 : 0.35, 1] : [0, 1]
        opacity.duration = reduceMotion ? 0.14 : (opening ? NotchMotion.revealDuration : NotchMotion.departureDuration) * timeScale
        opacity.timingFunctions = opening ? [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)] : [CAMediaTimingFunction(name: .easeIn)]
        content.layer?.add(opacity, forKey: "notch.contentOpacity")
        CATransaction.commit()
        let current = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
            catch { return }
            guard let self, self.generation == token else { return }
            self.finishTransition()
            self.transitionTask = nil
        }
        transitionTask = current
        await current.value
    }

    func contains(_ globalPoint: CGPoint) -> Bool {
        if let geometry, phase != .hidden, geometry.triggerContains(globalPoint) { return true }
        let local = CGPoint(x: globalPoint.x - panel.frame.minX, y: globalPoint.y - panel.frame.minY)
        if phase == .expanding, let geometry { return contour(geometry.expandedSize).contains(local) }
        return (silhouette.presentation()?.path ?? silhouette.path)?.contains(local) == true
    }

    func capture(to url: URL) throws {
        try NativeSnapshot.write(view: canvas, contour: silhouette.path, to: url)
    }

    var arrivalAnchorDrift: CGFloat {
        guard let layer = content.layer,
              let animation = layer.animation(forKey: "notch.contentScale") as? CABasicAnimation,
              let value = animation.fromValue as? NSValue else { return 0 }
        let transform = value.caTransform3DValue
        let top = CGPoint(x: content.bounds.midX, y: layer.contentsAreFlipped() ? 0 : content.bounds.height)
        let anchor = CGPoint(x: layer.anchorPoint.x * content.bounds.width, y: layer.anchorPoint.y * content.bounds.height)
        let x = (top.x - anchor.x) * transform.m11 + transform.m41 + anchor.x
        let y = (top.y - anchor.y) * transform.m22 + transform.m42 + anchor.y
        return hypot(top.x - x, top.y - y)
    }

    // Read-only probes for actual CA configuration, separate from pure profile tests.
    var shapeAnimation: CAKeyframeAnimation? { silhouette.animation(forKey: "notch.shape") as? CAKeyframeAnimation }
    var opacityAnimation: CAKeyframeAnimation? { content.layer?.animation(forKey: "notch.contentOpacity") as? CAKeyframeAnimation }
    var hasAnimations: Bool { !(silhouette.animationKeys() ?? []).isEmpty || !(content.layer?.animationKeys() ?? []).isEmpty }
}
