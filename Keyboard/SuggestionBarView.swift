import UIKit

struct Suggestion {
    let title: String   // what is shown (may have quotes)
    let value: String   // what is inserted
    let primary: Bool   // bold: applied automatically by autocorrect
}

/// The strip above the keys: word suggestions while typing, tool buttons otherwise.
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

    private let dismissButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private let toolsButton = UIButton(type: .system)
    private let calculatorButton = UIButton(type: .system)
    private let languageButton = UIButton(type: .system)
    private let pasteButton = UIButton(type: .system)
    private let arrowsButton = UIButton(type: .system)
    private let gifButton = UIButton(type: .system)
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
        configure(emojiButton, symbol: "face.smiling", action: #selector(emojiTapped))
        configure(clipboardButton, symbol: "list.bullet.clipboard", action: #selector(clipboardTapped))
        configure(pasteButton, symbol: "doc.on.clipboard", action: #selector(pasteTapped))
        configure(arrowsButton, symbol: "arrow.up.and.down.and.arrow.left.and.right", action: #selector(arrowsTapped))
        configure(toolsButton, symbol: "square.grid.2x2", action: #selector(toolsTapped))
        configure(calculatorButton, symbol: "plusminus.circle", action: #selector(calculatorTapped))
        gifButton.setTitle("GIF", for: .normal)
        gifButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .heavy)
        gifButton.addTarget(self, action: #selector(gifTapped), for: .touchUpInside)
        addSubview(gifButton)
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
        addSubview(button)
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.background
        for b in [dismissButton, emojiButton, clipboardButton, toolsButton, calculatorButton, pasteButton] { b.tintColor = theme.text }
        arrowsButton.tintColor = arrowsOn ? theme.accent : theme.text
        languageButton.setTitleColor(theme.text, for: .normal)
        gifButton.setTitleColor(theme.text, for: .normal)
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
        arrowsButton.tintColor = on ? theme.accent : theme.text
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
        emojiButton.isHidden = false
        clipboardButton.isHidden = false
        toolsButton.isHidden = false
        calculatorButton.isHidden = false
        pasteButton.isHidden = false
        arrowsButton.isHidden = false
        gifButton.isHidden = false
        suggestionButtons.forEach { $0.isHidden = true }
        dividers.forEach { $0.isHidden = true }
    }

    /// Up to 3 suggestions, shown left / middle / right.
    func show(_ suggestions: [Suggestion]) {
        guard !suggestions.isEmpty else { showTools(); return }
        showingSuggestions = true
        emojiButton.isHidden = true
        clipboardButton.isHidden = true
        toolsButton.isHidden = true
        calculatorButton.isHidden = true
        pasteButton.isHidden = true
        arrowsButton.isHidden = true
        gifButton.isHidden = true
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
        let right = bounds.width - 4
        // Right side, from the edge inward.
        let tools = [toolsButton, arrowsButton, pasteButton, clipboardButton, gifButton, calculatorButton, emojiButton]
        let w = min(40, (bounds.width - 100) / CGFloat(tools.count))
        for (i, b) in tools.enumerated() {
            b.frame = CGRect(x: right - w * CGFloat(i + 1), y: 0, width: w, height: h)
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
    @objc private func emojiTapped() { onEmoji?() }
    @objc private func clipboardTapped() { onClipboard?() }
    @objc private func toolsTapped() { onTools?() }
    @objc private func calculatorTapped() { onCalculator?() }
    @objc private func languageTapped() { onLanguage?() }
    @objc private func pasteTapped() { onPaste?() }
    @objc private func arrowsTapped() { onArrows?() }
    @objc private func gifTapped() { onGif?() }

    @objc private func suggestionTapped(_ sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        onSuggestion?(values[sender.tag])
    }
}
