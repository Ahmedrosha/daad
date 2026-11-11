import UIKit

struct Suggestion {
    let title: String   // what is shown (may have quotes)
    let value: String   // what is inserted
    let primary: Bool   // bold: applied automatically by autocorrect
}

/// Lets the bar scroll sideways even when the drag starts on a button.
private final class BarScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// The strip above the keys: word suggestions while typing, tool buttons otherwise.
/// Hide and language stay on the left; the other buttons follow the user's order and scroll sideways.
final class SuggestionBarView: UIView {
    var onSuggestion: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onTools: (() -> Void)?
    var onCalculator: (() -> Void)?
    var onLanguage: (() -> Void)?
    var onPaste: (() -> Void)?
    var onArrows: (() -> Void)?
    var onGif: (() -> Void)?
    var onCopyAll: (() -> Void)?
    var onDeleteAll: (() -> Void)?

    private let dismissButton = UIButton(type: .system)
    private let languageButton = UIButton(type: .system)
    private let toolScroll = BarScrollView()
    private var itemButtons: [(BarItem, UIButton)] = []
    private var items: [BarItem] = []
    private var needsScrollToEnd = true
    private let toastLabel = UILabel()
    private var toastWork: DispatchWorkItem?
    private var arrowsOn = false
    private var suggestionButtons: [UIButton] = []
    private var dividers: [UIView] = []
    private var values: [String] = []
    private var showingSuggestions = false
    private var theme = KeyboardTheme.make(dark: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure(dismissButton, symbol: "keyboard.chevron.compact.down", action: #selector(dismissTapped))
        addSubview(dismissButton)
        toolScroll.showsHorizontalScrollIndicator = false
        toolScroll.delaysContentTouches = false
        toolScroll.alwaysBounceHorizontal = false
        addSubview(toolScroll)
        setItems(BarItem.allCases.filter { $0 != .deleteAll && $0 != .copyAll })
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        toastLabel.numberOfLines = 2
        toastLabel.adjustsFontSizeToFitWidth = true
        toastLabel.minimumScaleFactor = 0.7
        toastLabel.isHidden = true
        addSubview(toastLabel)
        languageButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        languageButton.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        addSubview(languageButton)
        for i in 0..<3 {
            let b = UIButton(type: .system)
            b.tag = i
            b.titleLabel?.lineBreakMode = .byTruncatingMiddle
            b.addTarget(self, action: #selector(suggestionTapped(_:)), for: .touchUpInside)
            addSubview(b)
            suggestionButtons.append(b)
            if i < 2 {
                let d = UIView()
                addSubview(d)
                dividers.append(d)
            }
        }
        showTools()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ button: UIButton, symbol: String, action: Selector) {
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// The tool buttons to show, left to right.
    func setItems(_ new: [BarItem]) {
        guard new != items else { return }
        items = new
        itemButtons.forEach { $0.1.removeFromSuperview() }
        itemButtons = new.map { item in
            let b = UIButton(type: .system)
            switch item {
            case .gif:
                b.setTitle("GIF", for: .normal)
                b.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .heavy)
            case .calculator:
                b.setImage(DaadIcons.calculator(size: 20), for: .normal)
            default:
                let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
                b.setImage(UIImage(systemName: item.symbol ?? "questionmark", withConfiguration: config), for: .normal)
            }
            b.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            toolScroll.addSubview(b)
            return (item, b)
        }
        apply(theme: theme)
        needsScrollToEnd = true
        setNeedsLayout()
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.background
        dismissButton.tintColor = theme.text
        for (item, b) in itemButtons {
            b.tintColor = item == .arrows && arrowsOn ? theme.accent : theme.text
            b.setTitleColor(theme.text, for: .normal)
        }
        languageButton.setTitleColor(theme.text, for: .normal)
        toastLabel.textColor = theme.text
        toastLabel.backgroundColor = theme.background
        for b in suggestionButtons { b.setTitleColor(theme.text, for: .normal) }
        for d in dividers { d.backgroundColor = theme.secondaryText.withAlphaComponent(0.35) }
    }

    /// A short message over the bar for a couple of seconds.
    func flash(_ text: String) {
        toastWork?.cancel()
        toastLabel.text = text
        toastLabel.isHidden = false
        bringSubviewToFront(toastLabel)
        let work = DispatchWorkItem { [weak self] in self?.toastLabel.isHidden = true }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    /// Arrow-row button is highlighted while the arrows are shown.
    func setArrowsOn(_ on: Bool) {
        arrowsOn = on
        for (item, b) in itemButtons where item == .arrows { b.tintColor = on ? theme.accent : theme.text }
    }

    /// Shows the language the button switches to.
    /// Shows which keyboard is on now: ع, En or ع+En.
    func setInputMode(_ mode: InputMode) {
        languageButton.titleLabel?.font = UIFont.systemFont(ofSize: mode == .dual ? 13 : 18, weight: .medium)
        languageButton.setTitle(mode.shortLabel, for: .normal)
    }

    func showTools() {
        showingSuggestions = false
        values = []
        toolScroll.isHidden = false
        suggestionButtons.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
    }

    /// Up to 3 suggestions, shown left / middle / right.
    func show(_ suggestions: [Suggestion]) {
        guard !suggestions.isEmpty else { showTools(); return }
        showingSuggestions = true
        toolScroll.isHidden = true
        values = suggestions.map { $0.value }
        for (i, b) in suggestionButtons.enumerated() {
            if i < suggestions.count {
                let s = suggestions[i]
                b.isHidden = false
                b.setTitle(s.title, for: .normal)
                b.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: s.primary ? .semibold : .regular)
            } else {
                b.isHidden = true
            }
        }
        for (i, d) in dividers.enumerated() { d.isHidden = i + 1 >= suggestions.count }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        dismissButton.frame = CGRect(x: 4, y: 0, width: 44, height: h)
        languageButton.frame = CGRect(x: 50, y: 0, width: 44, height: h)
        // Tool buttons: right-aligned when they fit, otherwise the strip scrolls sideways.
        toolScroll.frame = CGRect(x: 96, y: 0, width: max(0, bounds.width - 100), height: h)
        let w: CGFloat = 40
        let total = w * CGFloat(itemButtons.count)
        let lead = max(0, toolScroll.bounds.width - total)
        for (i, entry) in itemButtons.enumerated() {
            entry.1.frame = CGRect(x: lead + w * CGFloat(i), y: 0, width: w, height: h)
        }
        toolScroll.contentSize = CGSize(width: max(total, toolScroll.bounds.width), height: h)
        // Like before, the bar is anchored on the right: start scrolled to the right end.
        if needsScrollToEnd, toolScroll.bounds.width > 0 {
            needsScrollToEnd = false
            toolScroll.contentOffset = CGPoint(x: toolScroll.contentSize.width - toolScroll.bounds.width, y: 0)
        }

        let start: CGFloat = 98
        let width = (bounds.width - start - 4) / 3
        for (i, b) in suggestionButtons.enumerated() {
            b.frame = CGRect(x: start + CGFloat(i) * width, y: 0, width: width, height: h)
        }
        toastLabel.frame = CGRect(x: 98, y: 0, width: bounds.width - 102, height: h)
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: start + CGFloat(i + 1) * width, y: h * 0.25, width: 1, height: h * 0.5)
        }
    }

    @objc private func dismissTapped() { onDismiss?() }
    @objc private func languageTapped() { onLanguage?() }

    @objc private func itemTapped(_ sender: UIButton) {
        guard let item = itemButtons.first(where: { $0.1 === sender })?.0 else { return }
        switch item {
        case .emoji: onEmoji?()
        case .calculator: onCalculator?()
        case .gif: onGif?()
        case .clipboard: onClipboard?()
        case .paste: onPaste?()
        case .arrows: onArrows?()
        case .copyAll: onCopyAll?()
        case .deleteAll: onDeleteAll?()
        case .tools: onTools?()
        }
    }

    @objc private func suggestionTapped(_ sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        onSuggestion?(values[sender.tag])
    }
}
