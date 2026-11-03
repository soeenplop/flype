import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reports finger down and up on character keys as soon as they happen.
/// The system can hold touches back from views near the screen edges, but recognizers still see them.
/// It only observes: it never recognizes, cancels or delays anything.
final class KeyboardPreviewGesture: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onDown: ((KeyboardKeyButton) -> Void)?
    var onUp: ((KeyboardKeyButton) -> Void)?
    private var keys: [ObjectIdentifier: KeyboardKeyButton] = [:]

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    func isDown(on key: KeyboardKeyButton) -> Bool { keys.values.contains { $0 === key } }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard let key = touch.view as? KeyboardKeyButton else { continue }
            keys[ObjectIdentifier(touch)] = key
            #if DEBUG
                KeyboardTouchDiagnostics.shared.previewBegan(touch)
            #endif
            onDown?(key)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, with: event) }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches, with: event) }

    private func finish(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard let key = keys.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            if !isDown(on: key) { onUp?(key) }
        }
        let active = event.allTouches?.contains { $0.phase != .ended && $0.phase != .cancelled } ?? false
        if !active { state = .failed }
    }

    override func reset() {
        super.reset()
        keys.removeAll()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}
