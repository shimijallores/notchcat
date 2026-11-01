import AppKit
import QuartzCore

/// Hosts the SwiftUI content and animates the notch-shaped silhouette with Core Animation.
///
/// The SwiftUI tree is laid out once at full size and never re-rendered during the animation.
/// Only a mask (the black silhouette) and a transform/opacity on the content change, and those run
/// in the render server, so the motion stays smooth even while the main thread is busy.
final class DropContainerView: NSView {
    let host: NSView
    private let holder = NSView()
    private let maskLayer = CALayer()

    private var notchSize = CGSize(width: 180, height: 32)
    private var fullRadius: CGFloat = 30
    private(set) var isExpanded = false

    private static let collapsedRadius: CGFloat = 9
    /// The silhouette extends this far above the window so its top edge is always clipped by the
    /// window itself, never rasterized on a fractional pixel inside it.
    private static let topBleed: CGFloat = 8
    private static let housing = NSColor(srgbRed: 0.035, green: 0.035, blue: 0.04, alpha: 1)

    /// Quick out from under the bezel, nearly critically damped: a soft ease-out with no rubber band.
    private enum Spring {
        // Damping >= 2*sqrt(stiffness*mass) is critically damped: fast start, soft landing, never overshoots
        // the container (an oversized mask is what used to flash a row of menu bar at the top).
        static let open = (mass: CGFloat(1), stiffness: CGFloat(560), damping: CGFloat(48))
        static let close = (mass: CGFloat(1), stiffness: CGFloat(680), damping: CGFloat(54))
    }

    init(host: NSView) {
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.housing.cgColor

        holder.wantsLayer = true
        addSubview(holder)
        holder.addSubview(host)

        maskLayer.backgroundColor = NSColor.black.cgColor
        maskLayer.anchorPoint = CGPoint(x: 0.5, y: 1)          // pinned to the top edge, centered
        maskLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // bottom corners only
        maskLayer.cornerCurve = .continuous
        layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        holder.frame = bounds
        host.frame = holder.bounds
        applyModel()
    }

    // MARK: - State

    func configure(notch: CGSize, radius: CGFloat, expanded: Bool) {
        notchSize = notch
        fullRadius = radius
        isExpanded = expanded
        applyModel()
    }

    private var slide: CGFloat { min(bounds.height * 0.28, 90) }

    /// Writes the model values for the current state without implicit animations.
    private func applyModel() {
        guard let rootLayer = layer, let holderLayer = holder.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bleed = Self.topBleed
        maskLayer.position = CGPoint(x: bounds.midX, y: bounds.maxY + bleed)
        let shape = isExpanded ? bounds.size : notchSize
        maskLayer.bounds = CGRect(x: 0, y: 0, width: shape.width, height: shape.height + bleed)
        maskLayer.cornerRadius = isExpanded ? fullRadius : Self.collapsedRadius
        holderLayer.opacity = isExpanded ? 1 : 0
        // Content rides down with the silhouette (positive y is up in layer space).
        rootLayer.sublayerTransform = isExpanded
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, slide, 0)
        CATransaction.commit()
    }

    func debugMask() -> String {
        let pb = maskLayer.presentation()?.bounds ?? maskLayer.bounds
        let pp = maskLayer.presentation()?.position ?? maskLayer.position
        return String(format: "visibleH=%.1f w=%.1f posY=%.2f contH=%.1f", pb.height - Self.topBleed, pb.width, pp.y,
                      bounds.height)
    }

    // MARK: - Animation

    /// Animates to the expanded or collapsed state, continuing from wherever the last animation is.
    func animate(expanded: Bool) {
        guard let rootLayer = layer, let holderLayer = holder.layer else { return }

        let fromBounds = maskLayer.presentation()?.bounds ?? maskLayer.bounds
        let fromRadius = maskLayer.presentation()?.cornerRadius ?? maskLayer.cornerRadius
        let fromOpacity = holderLayer.presentation()?.opacity ?? holderLayer.opacity
        let fromSlide = (rootLayer.presentation()?.sublayerTransform ?? rootLayer.sublayerTransform).m42

        isExpanded = expanded
        applyModel()

        let spring = expanded ? Spring.open : Spring.close

        func springAnimation(_ keyPath: String, from: Any, to: Any) -> CASpringAnimation {
            let a = CASpringAnimation(keyPath: keyPath)
            a.mass = spring.mass
            a.stiffness = spring.stiffness
            a.damping = spring.damping
            a.fromValue = from
            a.toValue = to
            a.duration = a.settlingDuration
            return a
        }

        maskLayer.add(springAnimation("bounds", from: NSValue(rect: fromBounds), to: NSValue(rect: maskLayer.bounds)),
                      forKey: "bounds")
        maskLayer.add(springAnimation("cornerRadius", from: fromRadius, to: maskLayer.cornerRadius),
                      forKey: "radius")

        let targetSlide = rootLayer.sublayerTransform.m42
        rootLayer.add(springAnimation("sublayerTransform.translation.y", from: fromSlide, to: targetSlide),
                      forKey: "slide")

        // Content crossfades: in once the silhouette is mostly open, out quickly on the way back.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = expanded ? 1 : 0
        fade.duration = expanded ? 0.16 : 0.10
        fade.beginTime = CACurrentMediaTime() + (expanded ? 0.05 : 0)
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: expanded ? .easeOut : .easeIn)
        holderLayer.add(fade, forKey: "fade")
    }
}
