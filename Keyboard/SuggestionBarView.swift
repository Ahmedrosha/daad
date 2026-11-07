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

    private let dismissButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let clipboardButton = UIButton(type: .system)
    private let toolsButton = UIButton(type: .system)
    private var suggestionButtons: [UIButton] = []
    private var dividers: [UIView] = []
    private var values: [String] = []
    private var showingSuggestions = false
    private var theme = KeyboardTheme.make(dark: false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure(dismissButton, symbol: "keyboard.chevron.compact.down", action: #selector(dismissTapped))
        configure(emojiButton, symbol: "face.smiling", action: #selector(emojiTapped))
        configure(clipboardButton, symbol: "doc.on.clipboard", action: #selector(clipboardTapped))
        configure(toolsButton, symbol: "square.grid.2x2", action: #selector(toolsTapped))
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
        for b in [dismissButton, emojiButton, clipboardButton, toolsButton] { b.tintColor = theme.text }
        for b in suggestionButtons { b.setTitleColor(theme.text, for: .normal) }
        for d in dividers { d.backgroundColor = theme.secondaryText.withAlphaComponent(0.35) }
    }

    func showTools() {
        showingSuggestions = false
        values = []
        emojiButton.isHidden = false
        clipboardButton.isHidden = false
        toolsButton.isHidden = false
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
        let right = bounds.width - 4
        toolsButton.frame = CGRect(x: right - 44, y: 0, width: 44, height: h)
        clipboardButton.frame = CGRect(x: right - 92, y: 0, width: 44, height: h)
        emojiButton.frame = CGRect(x: right - 140, y: 0, width: 44, height: h)

        let start: CGFloat = 52
        let width = (bounds.width - start - 4) / 3
        for (i, b) in suggestionButtons.enumerated() {
            b.frame = CGRect(x: start + CGFloat(i) * width, y: 0, width: width, height: h)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: start + CGFloat(i + 1) * width, y: h * 0.25, width: 1, height: h * 0.5)
        }
    }

    @objc private func dismissTapped() { onDismiss?() }
    @objc private func emojiTapped() { onEmoji?() }
    @objc private func clipboardTapped() { onClipboard?() }
    @objc private func toolsTapped() { onTools?() }

    @objc private func suggestionTapped(_ sender: UIButton) {
        guard values.indices.contains(sender.tag) else { return }
        onSuggestion?(values[sender.tag])
    }
}
