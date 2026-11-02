import AppKit

/// The black shape drawn at the top of a screen with no hardware notch: either a notch flush with the
/// top edge (rounded at the bottom, like the real one) or a floating capsule "island" below it.
final class FakeNotchView: NSView {
    var style: FakeNotchStyle = .notch { didSet { updateShape() } }
    var onClick: () -> Void = {}

    private static let notchRadius: CGFloat = 9

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DropContainerView.housing.cgColor
        layer?.cornerCurve = .continuous
        updateShape()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        updateShape()
    }

    private func updateShape() {
        guard let layer else { return }
        switch style {
        case .island:
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            layer.cornerRadius = bounds.height / 2
        case .notch, .off:
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]   // bottom corners only
            layer.cornerRadius = Self.notchRadius
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}
