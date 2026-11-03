import FlypeCore
import UIKit

/// Fixed stop square inside a circle; only the outer contour reacts to sound.
/// A spinner takes its place while the text is being prepared.
final class RecordingLevelView: UIView {
    private let control = ReactiveStopButton(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .large)
    var stopButton: UIButton { control }
    var showsProgress = false {
        didSet {
            control.isHidden = showsProgress
            if showsProgress { spinner.startAnimating() } else { spinner.stopAnimating() }
        }
    }
    private var dictationID: UUID?
    private var lastSample: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(control)
        addSubview(spinner)
        spinner.hidesWhenStopped = true
        spinner.color = KeyboardKeyAppearance.accent
        spinner.isAccessibilityElement = true
        spinner.accessibilityLabel = L10n.text("Dein Text entsteht …")
        control.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.centerXAnchor.constraint(equalTo: centerXAnchor),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: 144),
            control.heightAnchor.constraint(equalToConstant: 144),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ session: VoiceSessionState) {
        if dictationID != session.dictationID {
            control.level = 0
            dictationID = session.dictationID
            lastSample = nil
        }
        guard lastSample != session.updatedAt else { return }
        lastSample = session.updatedAt
        let value = session.inputLevel ?? 0
        control.level = value.isFinite ? min(1, max(0, value)) : 0
    }
}

private final class ReactiveStopButton: UIButton {
    var level = 0.0 { didSet { setNeedsDisplay() } }
    override var isHighlighted: Bool { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        accessibilityLabel = L10n.text("Transkription stoppen und einfügen")
        accessibilityTraits = .button
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let strength = CGFloat(level)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius = min(bounds.width, bounds.height) * 0.35

        // Stable circular button and square stop glyph; only the surrounding
        // contour follows the current level, without a delayed animation.
        let circle = CGRect(
            x: center.x - baseRadius, y: center.y - baseRadius,
            width: baseRadius * 2, height: baseRadius * 2)
        KeyboardKeyAppearance.accent.withAlphaComponent(isHighlighted ? 0.18 : 0.08).setFill()
        UIBezierPath(ovalIn: circle).fill()

        // One circular path with a single stroke width around its entire perimeter.
        let radius = baseRadius + 3
        let contour = UIBezierPath(
            ovalIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2))
        KeyboardKeyAppearance.accent.withAlphaComponent(0.7).setStroke()
        contour.lineWidth = 2 + strength * 6
        contour.stroke()

        let square = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        KeyboardKeyAppearance.accent.setFill()
        UIBezierPath(roundedRect: square, cornerRadius: 4).fill()
    }
}
