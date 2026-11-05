import FlypeCore
import UIKit

/// Fixed stop square inside a circle; only the outer contour reacts to sound.
/// A spinner takes its place while the text is being prepared. Cancelling keeps its place in both.
final class RecordingLevelView: UIView {
    private let control = ReactiveStopButton(frame: .zero)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let cancelControl: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = KeyboardKeyAppearance.foreground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = .systemFont(ofSize: 15, weight: .medium)
            return attributes
        }
        return UIButton(configuration: configuration)
    }()
    private let listening = UILabel()
    private let duration = UILabel()
    private let working = UILabel()
    private let stage = UILabel()
    var stopButton: UIButton { control }
    var cancelButton: UIButton { cancelControl }
    private var dictationID: UUID?
    private var lastSample: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.hidesWhenStopped = true
        spinner.color = KeyboardKeyAppearance.accent
        for label in [listening, working] {
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.textColor = KeyboardKeyAppearance.foreground
        }
        for label in [duration, stage] {
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            label.textColor = .secondaryLabel
        }
        let workingStack = UIStackView(arrangedSubviews: [spinner, working, stage])
        workingStack.axis = .vertical
        workingStack.alignment = .center
        workingStack.spacing = 6
        workingStack.setCustomSpacing(12, after: spinner)
        workingStack.isUserInteractionEnabled = false
        let views: [UIView] = [control, workingStack, cancelControl, listening, duration]
        for view in views {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            cancelControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            cancelControl.topAnchor.constraint(equalTo: topAnchor),
            cancelControl.heightAnchor.constraint(equalToConstant: 44),
            listening.centerXAnchor.constraint(equalTo: centerXAnchor),
            listening.centerYAnchor.constraint(equalTo: cancelControl.centerYAnchor),
            listening.leadingAnchor.constraint(greaterThanOrEqualTo: cancelControl.trailingAnchor, constant: 4),
            duration.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            duration.centerYAnchor.constraint(equalTo: cancelControl.centerYAnchor),
            control.centerXAnchor.constraint(equalTo: centerXAnchor),
            control.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 18),
            control.widthAnchor.constraint(equalToConstant: 144),
            control.heightAnchor.constraint(equalToConstant: 144),
            workingStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            workingStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 18),
            workingStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(phase: VoiceSessionState.Phase) {
        let isWorking = phase.isWorking
        control.isHidden = isWorking
        listening.isHidden = isWorking
        duration.isHidden = isWorking
        working.isHidden = !isWorking
        stage.isHidden = !isWorking
        if isWorking { spinner.startAnimating() } else { spinner.stopAnimating() }
        cancelControl.setTitle(L10n.text("Abbrechen"), for: .normal)
        listening.text = L10n.text("Ich höre zu …")
        working.text = L10n.text("Dein Text entsteht …")
        stage.text = L10n.text(
            phase == .preparing
                ? "Flype wird vorbereitet" : phase == .cleaning ? "Wird bereinigt" : "Sprache wird erkannt")
    }

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
        let seconds = Int(session.recordingDuration ?? 0)
        let text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        if duration.text != text { duration.text = text }
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
