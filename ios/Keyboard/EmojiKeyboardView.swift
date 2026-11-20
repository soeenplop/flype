import FlypeCore
import UIKit

/// The emoji pages laid out like the native keyboard: a grid scrolling sideways, its page name above it,
/// and the way back to the letters, the pages and Delete along the bottom.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((String) -> Void)?
    var onLetters: (() -> Void)?
    let deleteButton = UIButton(type: .system)

    private var pages: [EmojiCatalog.Page] = []
    private let layout = EmojiGridLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let titleLabel = UILabel()
    private let lettersButton = UIButton(type: .system)
    private let categories = UIStackView()
    private var categoryButtons: [(EmojiCatalog.Category, UIButton)] = []
    private var shownCategory: EmojiCatalog.Category?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.accessibilityTraits = .header

        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        // The keyboard sits on the bottom edge, so automatic safe-area insets would cost a row.
        grid.contentInsetAdjustmentBehavior = .never
        // No bar covers the grid, so the system's soft edges would only blur the outer emoji.
        for edge in [grid.topEdgeEffect, grid.bottomEdgeEffect, grid.leftEdgeEffect, grid.rightEdgeEffect] {
            edge.isHidden = true
        }
        grid.dataSource = self
        grid.delegate = self
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: EmojiCell.identifier)

        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        lettersButton.tintColor = KeyboardKeyAppearance.foreground
        lettersButton.addAction(UIAction { [weak self] _ in self?.onLetters?() }, for: .touchUpInside)
        lettersButton.addAction(UIAction { _ in UIDevice.current.playInputClick() }, for: .touchDown)

        deleteButton.setImage(UIImage(systemName: "delete.left"), for: .normal)
        deleteButton.tintColor = KeyboardKeyAppearance.foreground
        deleteButton.accessibilityLabel = L10n.text("Löschen")
        deleteButton.addAction(UIAction { _ in UIDevice.current.playInputClick() }, for: .touchDown)

        categories.axis = .horizontal
        categories.distribution = .fillEqually
        let bottom = UIStackView(arrangedSubviews: [lettersButton, categories, deleteButton])
        bottom.axis = .horizontal
        bottom.spacing = 4

        for view in [titleLabel, grid, bottom] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            grid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 2),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 40),
            lettersButton.widthAnchor.constraint(equalToConstant: 48),
            deleteButton.widthAnchor.constraint(equalToConstant: 48),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Loads the recently used emoji again and starts at the first page, as the native keyboard does.
    func reload() {
        pages = EmojiCatalog.pages()
        rebuildCategoryButtons()
        grid.reloadData()
        layoutIfNeeded()
        grid.layoutIfNeeded()
        grid.setContentOffset(.zero, animated: false)
        showCategory(pages.first?.category)
    }

    private func rebuildCategoryButtons() {
        for (_, button) in categoryButtons { button.removeFromSuperview() }
        categoryButtons = pages.map { page in
            let button = UIButton(type: .system)
            button.setImage(
                UIImage(
                    systemName: page.category.symbol,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)),
                for: .normal)
            button.accessibilityLabel = page.category.title
            button.addAction(
                UIAction { [weak self] _ in self?.scroll(to: page.category) }, for: .touchUpInside)
            button.addAction(UIAction { _ in UIDevice.current.playInputClick() }, for: .touchDown)
            categories.addArrangedSubview(button)
            return (page.category, button)
        }
    }

    private func scroll(to category: EmojiCatalog.Category) {
        guard let section = pages.firstIndex(where: { $0.category == category }) else { return }
        if section == 0 {
            grid.setContentOffset(.zero, animated: false)
        } else if let frame = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: section))?.frame {
            let maxOffset = max(0, grid.contentSize.width - grid.bounds.width)
            let offset = min(frame.minX - 6, maxOffset)
            grid.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
        }
        showCategory(category)
    }

    private func showCategory(_ category: EmojiCatalog.Category?) {
        guard let category, category != shownCategory || titleLabel.text == nil else { return }
        shownCategory = category
        titleLabel.text = category.title.uppercased()
        for (value, button) in categoryButtons {
            let selected = value == category
            button.tintColor = selected ? KeyboardKeyAppearance.foreground : .secondaryLabel
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
    }

    /// The page whose emoji fill the left edge names the grid, as on the native keyboard.
    private func updateShownCategory() {
        let probe = CGPoint(x: grid.contentOffset.x + 20, y: grid.bounds.height / 2)
        if let path = grid.indexPathForItem(at: probe) ?? grid.indexPathsForVisibleItems.min() {
            showCategory(pages[path.section].category)
        }
    }

    // MARK: Grid

    func numberOfSections(in collectionView: UICollectionView) -> Int { pages.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages[section].emoji.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
        -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiCell.identifier, for: indexPath)
        if let cell = cell as? EmojiCell { cell.emoji = pages[indexPath.section].emoji[indexPath.item] }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        // Slightly wider than high, which keeps the columns apart like on the native keyboard.
        let side = cellSide
        return CGSize(width: floor(side * 1.15), height: side)
    }

    func collectionView(
        _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        // Leftover height is split above and below, so each page's columns stay aligned.
        let rows = rowCount
        let vertical = max(0, floor((collectionView.bounds.height - CGFloat(rows) * cellSide) / 2))
        return UIEdgeInsets(top: vertical, left: 6, bottom: vertical, right: 6)
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        UIDevice.current.playInputClick()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onSelect?(pages[indexPath.section].emoji[indexPath.item])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateShownCategory() }

    /// Five rows in portrait, fewer where the keyboard is low, as on the native keyboard.
    private var rowCount: Int { max(3, min(5, Int(grid.bounds.height / 34))) }
    private var cellSide: CGFloat {
        guard grid.bounds.height > 0 else { return 40 }
        return floor(grid.bounds.height / CGFloat(rowCount))
    }
}

/// Cell sizes follow the grid's height, which changes with the word row and the keyboard's own height.
private final class EmojiGridLayout: UICollectionViewFlowLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.height != collectionView?.bounds.height || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }

    /// A bounds change alone keeps the cached cell sizes, so the new height would not reach them.
    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        if let context = context as? UICollectionViewFlowLayoutInvalidationContext,
            newBounds.height != collectionView?.bounds.height
        {
            context.invalidateFlowLayoutDelegateMetrics = true
        }
        return context
    }
}

private final class EmojiCell: UICollectionViewCell {
    static let identifier = "emoji"
    private let label = UILabel()

    var emoji = "" {
        didSet {
            label.text = emoji
            accessibilityLabel = emoji
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        contentView.addSubview(label)
        selectedBackgroundView = nil
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        label.font = .systemFont(ofSize: floor(bounds.height * 0.72))
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? KeyboardKeyAppearance.pressedSurface : .clear }
    }
}
