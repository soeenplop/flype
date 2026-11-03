import FlypeCore
import UIKit

/// A single held touch slides across the alternatives and commits on release.
final class KeyboardAlternatesView: UIView {
    private var labels: [UILabel] = []
    private let selection = UIView()
    private var keyBottom: CGFloat = 0
    private(set) var selectedIndex: Int?

    init() {
        super.init(frame: .zero)
        isHidden = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = UIColor {
            $0.userInterfaceStyle == .dark ? UIColor(white: 0.23, alpha: 1) : UIColor(white: 0.98, alpha: 1)
        }
        layer.cornerRadius = 9
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 3)
        selection.backgroundColor = .systemGray3
        selection.layer.cornerRadius = 7
        addSubview(selection)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(titles: [String], source: CGRect, bounds: CGRect, extendsLeft: Bool) {
        for label in labels { label.removeFromSuperview() }
        let cellWidth = min(36, (bounds.width - 8) / CGFloat(titles.count))
        let width = cellWidth * CGFloat(titles.count) + 4
        let anchorIndex = extendsLeft ? titles.count - 1 : 0
        let desiredX = source.midX - CGFloat(anchorIndex) * cellWidth - cellWidth / 2 - 2
        frame = CGRect(
            x: max(4, min(bounds.width - width - 4, desiredX)),
            y: max(0, source.minY - 52), width: width, height: 50)
        keyBottom = source.maxY - frame.minY
        labels = titles.enumerated().map { index, title in
            let label = UILabel(frame: CGRect(x: 2 + CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: 50))
            label.text = title
            label.textColor = .label
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 22)
            addSubview(label)
            return label
        }
        isHidden = false
        updateSelection(anchorIndex)
    }

    func select(at point: CGPoint) {
        guard !isHidden else { return }
        let local = convert(point, from: superview)
        updateSelection(
            KeyboardAlternates.selection(
                x: local.x - 2, y: local.y, width: bounds.width - 4,
                height: bounds.height, keyBottom: keyBottom, count: labels.count))
    }

    private func updateSelection(_ index: Int?) {
        selectedIndex = index
        selection.isHidden = index == nil
        if let index {
            selection.frame = labels[index].frame.insetBy(dx: 1, dy: 3)
        }
    }
}
