import UIKit

struct KeyboardTheme {
    let background: UIColor
    let key: UIColor
    let specialKey: UIColor
    let pressedKey: UIColor
    let accent: UIColor
    let text: UIColor
    let secondaryText: UIColor
    let popup: UIColor
    let shadow: UIColor

    /// A named theme from the settings; "system" follows light/dark mode.
    static func make(style: String, dark: Bool) -> KeyboardTheme {
        func c(_ hex: Int, _ a: CGFloat = 1) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        }
        switch style {
        case "light": return make(dark: false)
        case "dark": return make(dark: true)
        case "ocean":
            return KeyboardTheme(background: c(0x0B2E4A), key: c(0x1E5B85), specialKey: c(0x154468), pressedKey: c(0x3A7FB0),
                                 accent: c(0x38BDF8), text: .white, secondaryText: c(0xBFDBFE), popup: c(0x2A6B98), shadow: .black)
        case "forest":
            return KeyboardTheme(background: c(0x14301F), key: c(0x2D6A47), specialKey: c(0x214F36), pressedKey: c(0x46895F),
                                 accent: c(0x4ADE80), text: .white, secondaryText: c(0xBBF7D0), popup: c(0x357A52), shadow: .black)
        case "purple":
            return KeyboardTheme(background: c(0x22163A), key: c(0x523486), specialKey: c(0x3E2768), pressedKey: c(0x7350AD),
                                 accent: c(0xC084FC), text: .white, secondaryText: c(0xE9D5FF), popup: c(0x5E3D99), shadow: .black)
        case "sand":
            return KeyboardTheme(background: c(0xE7DCC3), key: c(0xFFF9EE), specialKey: c(0xCBBC98), pressedKey: c(0xDCCFB0),
                                 accent: c(0xB45309), text: c(0x3B2F1E), secondaryText: c(0x7A6A4F), popup: c(0xFFF9EE), shadow: c(0x9C8B66))
        case "photo":
            // Keys see-through over the photo.
            return KeyboardTheme(background: .clear,
                                 key: dark ? UIColor(white: 0.15, alpha: 0.55) : UIColor(white: 1, alpha: 0.7),
                                 specialKey: dark ? UIColor(white: 0.05, alpha: 0.55) : UIColor(white: 0.85, alpha: 0.7),
                                 pressedKey: dark ? UIColor(white: 0.4, alpha: 0.7) : UIColor(white: 0.7, alpha: 0.8),
                                 accent: .systemBlue, text: dark ? .white : .black,
                                 secondaryText: dark ? UIColor(white: 0.85, alpha: 1) : UIColor(white: 0.25, alpha: 1),
                                 popup: dark ? UIColor(white: 0.2, alpha: 0.95) : .white, shadow: .black)
        default: return make(dark: dark)
        }
    }

    static func make(dark: Bool) -> KeyboardTheme {
        if dark {
            return KeyboardTheme(
                background: UIColor(white: 0.08, alpha: 1),
                key: UIColor(white: 0.36, alpha: 1),
                specialKey: UIColor(white: 0.22, alpha: 1),
                pressedKey: UIColor(white: 0.52, alpha: 1),
                accent: UIColor.systemBlue,
                text: .white,
                secondaryText: UIColor(white: 0.75, alpha: 1),
                popup: UIColor(white: 0.42, alpha: 1),
                shadow: UIColor.black)
        }
        return KeyboardTheme(
            background: UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1),
            key: .white,
            specialKey: UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1),
            pressedKey: UIColor(red: 0.74, green: 0.76, blue: 0.80, alpha: 1),
            accent: UIColor.systemBlue,
            text: .black,
            secondaryText: UIColor(white: 0.35, alpha: 1),
            popup: .white,
            shadow: UIColor(white: 0.45, alpha: 1))
    }
}

/// One key. It draws only; touches are handled by KeyboardView.
final class KeyView: UIView {
    let key: Key
    private let theme: KeyboardTheme
    private let face = UIView()
    private let label = UILabel()
    private let icon = UIImageView()
    private let hint = UILabel()

    var isHighlighted = false { didSet { updateColors() } }

    /// The visible key rectangle in KeyboardView coordinates.
    var faceFrameInParent: CGRect { face.frame.offsetBy(dx: frame.minX, dy: frame.minY) }

    private let look: KeyLook

    init(key: Key, theme: KeyboardTheme, look: KeyLook = KeyLook()) {
        self.key = key
        self.theme = theme
        self.look = look
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        face.layer.cornerRadius = 6
        face.layer.shadowColor = theme.shadow.cgColor
        face.layer.shadowOffset = CGSize(width: 0, height: 1)
        face.layer.shadowOpacity = 0.35
        face.layer.shadowRadius = 0
        addSubview(face)

        label.text = key.label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.baselineAdjustment = .alignCenters
        face.addSubview(label)

        if let up = key.upChar {
            hint.text = up
            hint.font = UIFont.systemFont(ofSize: 10)
            hint.textAlignment = .right
            face.addSubview(hint)
        }
        if let symbol = key.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            icon.image = UIImage(systemName: symbol, withConfiguration: config)
            icon.contentMode = .center
            face.addSubview(icon)
        }
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setLabel(_ text: String) { label.text = text }
    func resetLabel() { label.text = key.label }

    func setDimmed(_ dimmed: Bool) {
        label.alpha = dimmed ? 0.15 : 1
        icon.alpha = dimmed ? 0.15 : 1
    }

    private func updateColors() {
        let base: UIColor
        switch key.style {
        case .normal: base = theme.key
        case .special: base = theme.specialKey
        case .accent: base = theme.accent
        }
        face.backgroundColor = isHighlighted ? theme.pressedKey : base
        let textColor: UIColor = key.style == .accent ? .white : theme.text
        label.textColor = (key.action == .space) ? theme.secondaryText : textColor
        icon.tintColor = textColor
        hint.textColor = theme.secondaryText
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        face.frame = bounds.insetBy(dx: 3, dy: 5)
        label.frame = face.bounds.insetBy(dx: 2, dy: 0)
        hint.frame = CGRect(x: 2, y: 1, width: face.bounds.width - 5, height: 12)
        icon.frame = face.bounds
        if key.smallLabel {
            label.font = UIFont.systemFont(ofSize: 15)
        } else if let first = key.label.first, first.isNumber {
            label.font = look.font.font(size: min(24, face.bounds.height * 0.55) * look.numberScale)
        } else if let first = key.label.first, TextHelpers.isArabic(first) {
            label.font = look.font.font(size: min(26, face.bounds.height * 0.6) * look.letterScale)
        } else {
            label.font = look.font.font(size: min(24, face.bounds.height * 0.55) * look.letterScale)
        }
        face.layer.shadowPath = UIBezierPath(roundedRect: face.bounds, cornerRadius: 6).cgPath
    }
}

/// The bubble shown above a key while it is pressed.
final class KeyPopupView: UIView {
    private let label = UILabel()

    init(theme: KeyboardTheme) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = theme.popup
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.textColor = theme.text
        label.font = UIFont.systemFont(ofSize: 32)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ text: String, over face: CGRect, in container: CGRect) {
        label.text = text
        let width = max(face.width * 1.35, 44)
        let height = max(face.height * 1.15, 50)
        var x = face.midX - width / 2
        x = min(max(container.minX + 2, x), container.maxX - width - 2)
        // Keyboard extensions can't draw above their own area, so the top row's bubble overlaps the key.
        let y = max(container.minY, face.minY - height - 4)
        frame = CGRect(x: x, y: y, width: width, height: height)
        label.frame = bounds.insetBy(dx: 4, dy: 4)
        isHidden = false
    }

    func hide() { isHidden = true }
}

/// The strip of extra characters shown on a long press (أ إ آ …).
final class AlternatesView: UIView {
    private let items: [String]
    private var labels: [UILabel] = []
    private let theme: KeyboardTheme
    private(set) var selectedIndex = 0

    var selectedItem: String? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    init(items: [String], theme: KeyboardTheme) {
        self.items = items
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = theme.popup
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        for item in items {
            let l = UILabel()
            l.text = TextHelpers.display(item)
            l.textAlignment = .center
            l.font = UIFont.systemFont(ofSize: 24)
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.5
            l.layer.cornerRadius = 6
            l.layer.masksToBounds = true
            addSubview(l)
            labels.append(l)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func place(over face: CGRect, in container: CGRect) {
        let cell = min(max(face.width, 30), (container.width - 12) / CGFloat(max(items.count, 1)))
        let width = cell * CGFloat(items.count) + 8
        let height = max(face.height, 44)
        var x = face.midX - cell / 2 - 4
        x = min(max(container.minX + 2, x), container.maxX - width - 2)
        let y = max(container.minY, face.minY - height - 4)
        frame = CGRect(x: x, y: y, width: width, height: height)
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * cell, y: 4, width: cell, height: height - 8)
        }
        select(atX: face.midX)
    }

    /// x is in the parent (KeyboardView) coordinate space.
    func select(atX x: CGFloat) {
        let local = x - frame.minX - 4
        let cell = labels.first?.frame.width ?? 1
        let index = Int(floor(local / cell))
        selectedIndex = min(max(0, index), items.count - 1)
        for (i, l) in labels.enumerated() {
            let selected = i == selectedIndex
            l.backgroundColor = selected ? theme.accent : .clear
            l.textColor = selected ? .white : theme.text
        }
    }
}
