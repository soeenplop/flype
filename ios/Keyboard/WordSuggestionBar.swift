import UIKit

/// The whole row receives touches; labels never determine the hit area.
final class WordSuggestionBar: UIControl {
    var onBegin: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    private let labels = (0..<3).map { _ in UILabel() }
    private let separators = (0..<2).map { _ in UIView() }
    private let pressedBackground = UIView()
    private var pressedIndex: Int?
    private var words: [String] = []

    private final class CandidateAccessibilityElement: UIAccessibilityElement {
        var activate: (() -> Void)?
        override func accessibilityActivate() -> Bool {
            activate?()
            return true
        }
    }
    private var candidates: [CandidateAccessibilityElement] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        pressedBackground.backgroundColor = .systemGray4
        pressedBackground.layer.cornerRadius = 6
        pressedBackground.isUserInteractionEnabled = false
        pressedBackground.isHidden = true
        addSubview(pressedBackground)
        for label in labels {
            label.font = .systemFont(ofSize: 17)
            label.textColor = .label
            label.textAlignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.isUserInteractionEnabled = false
            addSubview(label)
        }
        for separator in separators {
            separator.backgroundColor = .separator
            separator.isUserInteractionEnabled = false
            addSubview(separator)
        }
        candidates = (0..<3).map { index in
            let element = CandidateAccessibilityElement(accessibilityContainer: self)
            element.accessibilityTraits = .button
            element.activate = { [weak self] in
                self?.onBegin?(index)
                self?.onSelect?(index)
            }
            return element
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(words: [String]) {
        self.words = Array(words.prefix(3))
        for index in 0..<3 {
            labels[index].text = words.indices.contains(index) ? words[index] : nil
            candidates[index].accessibilityLabel = labels[index].text.map { "Wortvorschlag: \($0)" }
        }
        accessibilityElements = Array(candidates.prefix(self.words.count))
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / 3
        for index in 0..<3 {
            let segment = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            // The label and highlight share the same vertical bounds, so UILabel
            // centers the word inside the full-size pressed background.
            labels[index].frame = segment.insetBy(dx: 6, dy: 0)
            candidates[index].accessibilityFrameInContainerSpace = segment
        }
        let pixel = 1 / (window?.screen.scale ?? 3)
        for index in 0..<2 {
            separators[index].frame = CGRect(
                x: CGFloat(index + 1) * width, y: (bounds.height - 21) / 2, width: pixel, height: 21)
        }
        updatePressedBackground()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard bounds.width > 0 else { return false }
        let point = touch.location(in: self)
        let index = min(2, max(0, Int(point.x / (bounds.width / 3))))
        guard words.indices.contains(index) else { return false }
        pressedIndex = index
        pressedBackground.isHidden = false
        updatePressedBackground()
        UIDevice.current.playInputClick()
        onBegin?(index)
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        pressedBackground.isHidden = !bounds.contains(touch.location(in: self))
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let selected = pressedIndex
        pressedIndex = nil
        pressedBackground.isHidden = true
        if let selected, let touch, bounds.contains(touch.location(in: self)) {
            onSelect?(selected)
        } else {
            onCancel?()
        }
    }
    override func cancelTracking(with event: UIEvent?) {
        pressedIndex = nil
        pressedBackground.isHidden = true
        onCancel?()
    }
    private func updatePressedBackground() {
        guard let pressedIndex else { return }
        let segmentWidth = bounds.width / 3
        pressedBackground.frame = CGRect(
            x: CGFloat(pressedIndex) * segmentWidth, y: 0,
            width: segmentWidth, height: bounds.height)
    }
}
