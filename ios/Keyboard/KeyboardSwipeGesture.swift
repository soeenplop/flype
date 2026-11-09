import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Turns one finger sliding across the letters into a swipe. Until then, keys behave exactly as they do without it:
/// a tap, a long press or a second finger makes this fail, and it never delays a touch.
/// Once it recognizes, UIKit cancels the touch on the starting key, so that key's letter is not typed.
final class KeyboardSwipeGesture: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Whether a swipe may start on this key, asked at touch-down and again when the finger has moved far enough.
    var canStart: ((KeyboardKeyButton) -> Bool)?
    /// Farther than a shaky tap or the long-press allowance, but reachable by moving to a neighboring key.
    var startDistance: () -> CGFloat = { 28 }
    var onBegin: (([CGPoint]) -> Void)?
    var onChange: (([CGPoint]) -> Void)?
    var onEnd: (([CGPoint]) -> Void)?
    var onCancel: (() -> Void)?

    private var tracked: UITouch?
    private var startKey: KeyboardKeyButton?
    private var points: [CGPoint] = []

    init() {
        super.init(target: nil, action: nil)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if tracked != nil {
            // Overlapping thumbs while typing are not a swipe. A stray finger cannot end one that already started.
            if state == .possible {
                state = .failed
            } else {
                for touch in touches { ignore(touch, for: event) }
            }
            return
        }
        let active = event.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? touches
        guard touches.count == 1, active.count == 1, let touch = touches.first,
            let key = touch.view as? KeyboardKeyButton, canStart?(key) == true
        else {
            state = .failed
            return
        }
        tracked = touch
        startKey = key
        points = [touch.location(in: view)]
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        for touch in event.coalescedTouches(for: tracked) ?? [tracked] { points.append(touch.location(in: view)) }
        guard state == .possible else {
            state = .changed
            onChange?(points)
            return
        }
        guard let first = points.first, let last = points.last,
            hypot(last.x - first.x, last.y - first.y) >= startDistance()
        else { return }
        guard let startKey, canStart?(startKey) == true else {
            state = .failed
            return
        }
        state = .began
        onBegin?(points)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        if state == .began || state == .changed {
            points.append(tracked.location(in: view))
            state = .ended
            onEnd?(points)
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        if state == .began || state == .changed {
            state = .cancelled
            onCancel?()
        } else {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        tracked = nil
        startKey = nil
        points = []
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}

/// The line that follows the finger. It never receives touches.
final class KeyboardSwipeTrail {
    let layer = CAShapeLayer()

    init() {
        layer.fillColor = nil
        layer.lineWidth = 5
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.zPosition = 10
        layer.isHidden = true
    }

    func show(_ points: [CGPoint], color: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.strokeColor = color.withAlphaComponent(0.55).cgColor
        layer.opacity = 1
        layer.isHidden = false
        let path = CGMutablePath()
        path.addLines(between: points)
        layer.path = path
        CATransaction.commit()
    }

    func fadeOut() {
        guard !layer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setCompletionBlock { [layer] in
            guard layer.opacity == 0 else { return }
            layer.isHidden = true
        }
        layer.opacity = 0
        CATransaction.commit()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.isHidden = true
        CATransaction.commit()
    }
}
