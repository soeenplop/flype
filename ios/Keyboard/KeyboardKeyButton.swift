import UIKit

/// Explicit pressed feedback instead of relying on UIButton's subtle tint change.
final class KeyboardKeyButton: UIButton {
    var normalSurface: UIColor = .clear { didSet { updateSurface() } }
    var pressedSurface: UIColor = KeyboardKeyAppearance.pressedSurface
    var touchRegion: CGRect?
    var popupText: String?
    var alternateCharacter: String?
    var highlightChanged: ((KeyboardKeyButton, Bool) -> Void)?
    /// The iPad's function keys carry their symbol in a lower corner.
    enum GlyphCorner { case center, bottomLeading, bottomTrailing }
    var glyphCorner = GlyphCorner.center { didSet { setNeedsLayout() } }
    /// Set while a finger on a two-character key has moved far enough up to select the upper character.
    private(set) var isSwipedUp = false
    var swipeChanged: ((KeyboardKeyButton, Bool) -> Void)?
    private var trackingStart: CGPoint?
    override var isHighlighted: Bool {
        didSet {
            updateSurface()
            highlightChanged?(self, isHighlighted)
        }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = KeyboardKeyAppearance.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        titleLabel?.font = .systemFont(ofSize: 22)
        setTitleColor(KeyboardKeyAppearance.foreground, for: .normal)
        tintColor = KeyboardKeyAppearance.foreground
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateSurface() { backgroundColor = isHighlighted ? pressedSurface : normalSurface }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        trackingStart = touch.location(in: self)
        setSwipedUp(false)
        return super.beginTracking(touch, with: event)
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if let trackingStart {
            let location = touch.location(in: self)
            let up = trackingStart.y - location.y
            setSwipedUp(up >= 14 && up > abs(location.x - trackingStart.x))
        }
        return super.continueTracking(touch, with: event)
    }
    /// The state stays until the next touch: the key's action reads it right after this.
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        swipeChanged?(self, false)
    }
    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        setSwipedUp(false)
    }
    private func setSwipedUp(_ value: Bool) {
        guard isSwipedUp != value else { return }
        isSwipedUp = value
        swipeChanged?(self, value)
    }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        placed(super.imageRect(forContentRect: contentRect))
    }
    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        placed(super.titleRect(forContentRect: contentRect))
    }
    private func placed(_ rect: CGRect) -> CGRect {
        let y = bounds.maxY - 11 - rect.height
        switch glyphCorner {
        case .center: return rect
        case .bottomLeading: return CGRect(x: 14, y: y, width: rect.width, height: rect.height)
        case .bottomTrailing:
            return CGRect(x: bounds.maxX - 14 - rect.width, y: y, width: rect.width, height: rect.height)
        }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        (touchRegion ?? bounds).union(bounds.insetBy(dx: -6, dy: -6)).contains(point)
    }

    #if DEBUG
        private var deliveredAt: TimeInterval?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let touch = touches.first {
                deliveredAt = ProcessInfo.processInfo.systemUptime
                KeyboardTouchDiagnostics.shared.touchBegan(touch)
            }
            super.touchesBegan(touches, with: event)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let deliveredAt {
                KeyboardTouchDiagnostics.shared.touchEnded(
                    pressDuration: ProcessInfo.processInfo.systemUptime - deliveredAt)
            }
            deliveredAt = nil
            super.touchesEnded(touches, with: event)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            if deliveredAt != nil { KeyboardTouchDiagnostics.shared.touchCancelled() }
            deliveredAt = nil
            super.touchesCancelled(touches, with: event)
        }
    #endif
}
