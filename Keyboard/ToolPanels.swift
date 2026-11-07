import UIKit

enum KeyboardTool: CaseIterable {
    case emoji, clipboard, translate, calculator, contacts, oneHanded, look, settings

    var symbol: String {
        switch self {
        case .emoji: return "face.smiling"
        case .clipboard: return "doc.on.clipboard"
        case .translate: return "character.bubble"
        case .calculator: return "plusminus.circle"
        case .contacts: return "person.crop.circle"
        case .oneHanded: return "hand.raised"
        case .look: return "textformat.size"
        case .settings: return "gearshape"
        }
    }

    func title(arabic: Bool) -> String {
        switch self {
        case .emoji: return arabic ? "إيموجي" : "Emoji"
        case .clipboard: return arabic ? "الحافظة" : "Clipboard"
        case .translate: return arabic ? "ترجمة" : "Translate"
        case .calculator: return arabic ? "حاسبة" : "Calculator"
        case .contacts: return arabic ? "جهات الاتصال" : "Contacts"
        case .oneHanded: return arabic ? "يد واحدة" : "One-handed"
        case .look: return arabic ? "الحجم والخط" : "Size & font"
        case .settings: return arabic ? "الإعدادات" : "Settings"
        }
    }
}

/// Small header used by every panel: back button + title.
final class PanelHeader: UIView {
    let backButton = UIButton(type: .system)
    let titleLabel = UILabel()
    let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        backButton.setImage(UIImage(systemName: "chevron.backward", withConfiguration: config), for: .normal)
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        actionButton.isHidden = true
        addSubview(backButton)
        addSubview(titleLabel)
        addSubview(actionButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(theme: KeyboardTheme, title: String) {
        backButton.tintColor = theme.text
        actionButton.tintColor = theme.accent
        titleLabel.textColor = theme.text
        titleLabel.text = title
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backButton.frame = CGRect(x: 4, y: 0, width: 48, height: bounds.height)
        actionButton.frame = CGRect(x: bounds.width - 96, y: 0, width: 90, height: bounds.height)
        titleLabel.frame = CGRect(x: 100, y: 0, width: bounds.width - 200, height: bounds.height)
    }
}

/// The grid of tools, like SwiftKey's toolbar.
final class ToolsPanelView: UIView {
    var onSelect: ((KeyboardTool) -> Void)?
    var onClose: (() -> Void)?

    private let header = PanelHeader()
    private var tiles: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(header)
        for (i, tool) in KeyboardTool.allCases.enumerated() {
            let b = UIButton(type: .system)
            b.tag = i
            b.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
            b.layer.cornerRadius = 10
            addSubview(b)
            tiles.append(b)
            _ = tool
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, arabic: Bool) {
        backgroundColor = theme.background
        header.apply(theme: theme, title: arabic ? "الأدوات" : "Tools")
        for (i, tool) in KeyboardTool.allCases.enumerated() {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: tool.symbol,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 24))
            config.imagePlacement = .top
            config.imagePadding = 8
            var title = AttributedString(tool.title(arabic: arabic))
            title.font = UIFont.systemFont(ofSize: 14)
            config.attributedTitle = title
            config.baseForegroundColor = theme.text
            tiles[i].configuration = config
            tiles[i].backgroundColor = theme.specialKey.withAlphaComponent(0.5)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
        let columns = 4
        let rows = Int(ceil(Double(tiles.count) / Double(columns)))
        let pad: CGFloat = 8
        let top: CGFloat = 48
        let w = (bounds.width - pad * CGFloat(columns + 1)) / CGFloat(columns)
        let h = (bounds.height - top - pad * CGFloat(rows + 1)) / CGFloat(rows)
        for (i, b) in tiles.enumerated() {
            let r = i / columns, c = i % columns
            b.frame = CGRect(x: pad + CGFloat(c) * (w + pad), y: top + pad + CGFloat(r) * (h + pad), width: w, height: h)
        }
    }

    @objc private func tileTapped(_ sender: UIButton) { onSelect?(KeyboardTool.allCases[sender.tag]) }
    @objc private func closeTapped() { onClose?() }
}

// MARK: - Calculator

enum Calculator {
    /// Evaluates + − × ÷ and %, with normal precedence. Returns nil for incomplete input.
    static func evaluate(_ expression: String) -> Double? {
        var tokens: [String] = []
        var number = ""
        for ch in expression {
            if ch.isNumber || ch == "." {
                number.append(ch)
            } else if "+−×÷%".contains(ch) {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(ch))
            }
        }
        if !number.isEmpty { tokens.append(number) }

        // Percent applies to the number before it.
        var flat: [String] = []
        for t in tokens {
            if t == "%", let last = flat.last, let v = Double(last) {
                flat[flat.count - 1] = String(v / 100)
            } else {
                flat.append(t)
            }
        }
        guard let first = flat.first, Double(first) != nil, let last = flat.last, Double(last) != nil else { return nil }

        var values: [Double] = []
        var ops: [String] = []
        func precedence(_ op: String) -> Int { (op == "×" || op == "÷") ? 2 : 1 }
        func apply() -> Bool {
            guard let op = ops.popLast(), values.count >= 2 else { return false }
            let b = values.removeLast(), a = values.removeLast()
            switch op {
            case "+": values.append(a + b)
            case "−": values.append(a - b)
            case "×": values.append(a * b)
            case "÷": values.append(b == 0 ? .nan : a / b)
            default: return false
            }
            return true
        }
        for t in flat {
            if let v = Double(t) {
                values.append(v)
            } else {
                while let top = ops.last, precedence(top) >= precedence(t) { guard apply() else { return nil } }
                ops.append(t)
            }
        }
        while !ops.isEmpty { guard apply() else { return nil } }
        guard values.count == 1, let result = values.first, result.isFinite else { return nil }
        return result
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
        let f = NumberFormatter()
        f.maximumFractionDigits = 8
        f.minimumIntegerDigits = 1
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}

final class CalculatorPanelView: UIView {
    var onInsert: ((String) -> Void)?
    var onClose: (() -> Void)?

    private let header = PanelHeader()
    private let display = UILabel()
    private let resultLabel = UILabel()
    private var buttons: [UIButton] = []
    private var expression = ""
    private var theme = KeyboardTheme.make(dark: false)

    private let layout: [[String]] = [
        ["C", "⌫", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "=", "↵"],
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(header)
        display.textAlignment = .right
        display.font = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .regular)
        display.adjustsFontSizeToFitWidth = true
        display.minimumScaleFactor = 0.5
        resultLabel.textAlignment = .right
        resultLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        addSubview(display)
        addSubview(resultLabel)
        for row in layout {
            for title in row {
                let b = UIButton(type: .system)
                b.setTitle(title, for: .normal)
                b.titleLabel?.font = UIFont.systemFont(ofSize: 22)
                b.layer.cornerRadius = 6
                b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                addSubview(b)
                buttons.append(b)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, arabic: Bool) {
        self.theme = theme
        backgroundColor = theme.background
        header.apply(theme: theme, title: arabic ? "الحاسبة" : "Calculator")
        display.textColor = theme.text
        resultLabel.textColor = theme.secondaryText
        for b in buttons {
            let t = b.title(for: .normal) ?? ""
            let isOp = "÷×−+%=↵".contains(t)
            b.backgroundColor = t == "↵" ? theme.accent : (isOp || t == "C" || t == "⌫" ? theme.specialKey : theme.key)
            b.setTitleColor(t == "↵" ? .white : theme.text, for: .normal)
        }
        expression = ""
        refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 40)
        display.frame = CGRect(x: 12, y: 40, width: bounds.width - 24, height: 30)
        resultLabel.frame = CGRect(x: 12, y: 70, width: bounds.width - 24, height: 20)
        let top: CGFloat = 94
        let rows = CGFloat(layout.count), cols: CGFloat = 4
        let w = bounds.width / cols, h = (bounds.height - top - 2) / rows
        for (i, b) in buttons.enumerated() {
            let r = CGFloat(i / 4), c = CGFloat(i % 4)
            b.frame = CGRect(x: c * w, y: top + r * h, width: w, height: h).insetBy(dx: 3, dy: 3)
        }
    }

    private func refresh() {
        display.text = expression.isEmpty ? "0" : expression
        if let v = Calculator.evaluate(expression), expression.contains(where: { "+−×÷%".contains($0) }) {
            resultLabel.text = "= " + Calculator.format(v)
        } else {
            resultLabel.text = nil
        }
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let t = sender.title(for: .normal) else { return }
        switch t {
        case "C": expression = ""
        case "⌫": if !expression.isEmpty { expression.removeLast() }
        case "=":
            if let v = Calculator.evaluate(expression) { expression = Calculator.format(v) }
        case "↵":
            // Writes the whole equation, e.g. "5+3 = 8", kept left-to-right inside Arabic text.
            var text = expression
            if let v = Calculator.evaluate(expression), expression.contains(where: { "+−×÷%".contains($0) }) {
                text = expression + " = " + Calculator.format(v)
            }
            if !text.isEmpty { onInsert?("\u{2066}" + text + "\u{2069}") }
        default:
            if "+−×÷%".contains(t), let last = expression.last, "+−×÷".contains(last) {
                expression.removeLast()   // replace the previous operator
            }
            expression += t
        }
        refresh()
    }

    @objc private func closeTapped() { onClose?() }
}

// MARK: - In-keyboard settings

final class SettingsPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenLook: (() -> Void)?

    private let header = PanelHeader()
    private let table = UITableView(frame: .zero, style: .grouped)
    private var theme = KeyboardTheme.make(dark: false)
    private var arabic = true

    private typealias Row = (setting: DaadSetting, ar: String, en: String)
    private let sections: [(ar: String, en: String, rows: [Row])] = [
        ("الكتابة", "Typing", [
            (.suggestions, "اقتراح الكلمات", "Word suggestions"),
            (.autocorrect, "التصحيح التلقائي", "Autocorrect"),
            (.glideTyping, "الكتابة بالسحب", "Glide typing"),
            (.emojiSuggestions, "اقتراح إيموجي", "Emoji suggestions"),
            (.blockOffensive, "منع الكلمات البذيئة", "Block offensive words"),
            (.quickPeriod, "نقطة بضغطتين على المسافة", "Double-space period"),
            (.autoCapitalize, "كابيتال أول الجملة", "Auto-capitalize"),
        ]),
        ("شكل الكيبورد", "Layout", [
            (.numberRow, "صف الأرقام", "Number row"),
            (.arabicDigits, "أرقام عربية ١٢٣", "Arabic digits ١٢٣"),
        ]),
        ("الإحساس", "Feel", [
            (.keySound, "صوت الضغط", "Key sound"),
            (.haptics, "اهتزاز الضغط", "Haptics"),
            (.keyPopups, "معاينة الحرف", "Key pop-ups"),
        ]),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        addSubview(header)
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = 44
        table.register(UITableViewCell.self, forCellReuseIdentifier: "s")
        addSubview(table)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, arabic: Bool) {
        self.theme = theme
        self.arabic = arabic
        backgroundColor = theme.background
        header.apply(theme: theme, title: arabic ? "الإعدادات" : "Settings")
        table.semanticContentAttribute = arabic ? .forceRightToLeft : .forceLeftToRight
        table.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 44)
        table.frame = CGRect(x: 0, y: 44, width: bounds.width, height: bounds.height - 44)
    }

    // Last section is a link to the size & font panel.
    func numberOfSections(in tableView: UITableView) -> Int { sections.count + 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section < sections.count ? sections[section].rows.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < sections.count else { return arabic ? "المظهر" : "Look" }
        return arabic ? sections[section].ar : sections[section].en
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "s", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = theme.text
        cell.backgroundColor = theme.key.withAlphaComponent(0.35)
        cell.semanticContentAttribute = arabic ? .forceRightToLeft : .forceLeftToRight
        if indexPath.section == sections.count {
            content.text = arabic ? "الحجم والخط" : "Size & font"
            content.image = UIImage(systemName: "textformat.size")
            content.imageProperties.tintColor = theme.text
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else {
            let row = sections[indexPath.section].rows[indexPath.row]
            content.text = arabic ? row.ar : row.en
            let toggle = UISwitch()
            toggle.isOn = SharedSettings.shared.bool(row.setting)
            toggle.tag = indexPath.section * 100 + indexPath.row
            toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == sections.count { onOpenLook?() }
    }

    @objc private func toggled(_ sender: UISwitch) {
        let row = sections[sender.tag / 100].rows[sender.tag % 100]
        SharedSettings.shared.set(sender.isOn, for: row.setting)
        onChange?()
    }

    @objc private func closeTapped() { onClose?() }
}

// MARK: - Size & font

/// Sliders for letter size, number size, key height and keyboard width, plus the key font.
final class LookPanelView: UIView {
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?

    private let header = PanelHeader()
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let preview = UIStackView()
    private var fontButtons: [UIButton] = []
    private var theme = KeyboardTheme.make(dark: false)
    private var arabic = true

    private struct SliderSpec {
        let titleAr: String
        let titleEn: String
        let range: ClosedRange<Float>
        let get: () -> Double
        let set: (Double) -> Void
    }

    private lazy var specs: [SliderSpec] = {
        let s = SharedSettings.shared
        return [
            SliderSpec(titleAr: "حجم الحروف", titleEn: "Letter size", range: 0.7...1.4,
                       get: { s.letterFontScale }, set: { s.letterFontScale = $0 }),
            SliderSpec(titleAr: "حجم الأرقام", titleEn: "Number size", range: 0.7...1.4,
                       get: { s.numberFontScale }, set: { s.numberFontScale = $0 }),
            SliderSpec(titleAr: "ارتفاع الكيبورد", titleEn: "Keyboard height", range: 40...64,
                       get: { s.keyHeight }, set: { s.keyHeight = $0 }),
            SliderSpec(titleAr: "عرض الكيبورد", titleEn: "Keyboard width", range: 0.7...1.0,
                       get: { s.keyboardWidthScale }, set: { s.keyboardWidthScale = $0 }),
        ]
    }()
    private var sliders: [UISlider] = []
    private var titles: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.backButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        header.actionButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        header.actionButton.isHidden = false
        addSubview(header)
        addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 6
        scroll.addSubview(stack)

        preview.axis = .horizontal
        preview.distribution = .fillEqually
        preview.spacing = 0
        preview.heightAnchor.constraint(equalToConstant: 50).isActive = true
        stack.addArrangedSubview(preview)

        for (i, spec) in specs.enumerated() {
            let title = UILabel()
            title.font = UIFont.systemFont(ofSize: 14)
            titles.append(title)
            stack.addArrangedSubview(title)
            let slider = UISlider()
            slider.minimumValue = spec.range.lowerBound
            slider.maximumValue = spec.range.upperBound
            slider.tag = i
            slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
            sliders.append(slider)
            stack.addArrangedSubview(slider)
        }

        let fontTitle = UILabel()
        fontTitle.font = UIFont.systemFont(ofSize: 14)
        fontTitle.tag = 99
        stack.addArrangedSubview(fontTitle)
        let fontScroll = UIScrollView()
        fontScroll.showsHorizontalScrollIndicator = false
        fontScroll.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let fontRow = UIStackView()
        fontRow.axis = .horizontal
        fontRow.spacing = 8
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        fontScroll.addSubview(fontRow)
        NSLayoutConstraint.activate([
            fontRow.leadingAnchor.constraint(equalTo: fontScroll.contentLayoutGuide.leadingAnchor),
            fontRow.trailingAnchor.constraint(equalTo: fontScroll.contentLayoutGuide.trailingAnchor),
            fontRow.topAnchor.constraint(equalTo: fontScroll.contentLayoutGuide.topAnchor),
            fontRow.bottomAnchor.constraint(equalTo: fontScroll.contentLayoutGuide.bottomAnchor),
            fontRow.heightAnchor.constraint(equalTo: fontScroll.frameLayoutGuide.heightAnchor),
        ])
        for (i, font) in KeyFont.allCases.enumerated() {
            let b = UIButton(type: .system)
            b.tag = i
            b.setTitle(" ض \(font.title) ", for: .normal)
            b.titleLabel?.font = font.font(size: 17)
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            b.addTarget(self, action: #selector(fontTapped(_:)), for: .touchUpInside)
            fontRow.addArrangedSubview(b)
            fontButtons.append(b)
        }
        stack.addArrangedSubview(fontScroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(theme: KeyboardTheme, arabic: Bool) {
        self.theme = theme
        self.arabic = arabic
        backgroundColor = theme.background
        header.apply(theme: theme, title: arabic ? "الحجم والخط" : "Size & font")
        header.actionButton.setTitle(arabic ? "إعادة ضبط" : "Reset", for: .normal)
        for (i, spec) in specs.enumerated() {
            titles[i].text = arabic ? spec.titleAr : spec.titleEn
            titles[i].textColor = theme.secondaryText
            titles[i].textAlignment = arabic ? .right : .left
            sliders[i].value = Float(spec.get())
            sliders[i].minimumTrackTintColor = theme.accent
        }
        if let fontTitle = stack.arrangedSubviews.first(where: { $0.tag == 99 }) as? UILabel {
            fontTitle.text = arabic ? "شكل الحروف" : "Key font"
            fontTitle.textColor = theme.secondaryText
            fontTitle.textAlignment = arabic ? .right : .left
        }
        refreshFonts()
        refreshPreview()
    }

    private func refreshFonts() {
        let current = KeyFont(rawValue: SharedSettings.shared.keyFont) ?? .system
        for (i, b) in fontButtons.enumerated() {
            let selected = KeyFont.allCases[i] == current
            b.backgroundColor = selected ? theme.accent : theme.key
            b.setTitleColor(selected ? .white : theme.text, for: .normal)
        }
    }

    private func refreshPreview() {
        preview.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let look = KeyLook.current
        let samples = arabic ? ["ض", "ص", "ث", "ق", "ف", "١", "٢", "٣"] : ["q", "w", "e", "r", "t", "1", "2", "3"]
        for s in samples {
            preview.addArrangedSubview(KeyView(key: Key(action: .character(s), label: s), theme: theme, look: look))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 40)
        scroll.frame = CGRect(x: 0, y: 40, width: bounds.width, height: bounds.height - 40)
        let width = bounds.width - 32
        let size = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(x: 16, y: 4, width: width, height: size.height)
        scroll.contentSize = CGSize(width: bounds.width, height: size.height + 12)
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        specs[sender.tag].set(Double(sender.value))
        refreshPreview()
        onChange?()
    }

    @objc private func fontTapped(_ sender: UIButton) {
        SharedSettings.shared.keyFont = KeyFont.allCases[sender.tag].rawValue
        refreshFonts()
        refreshPreview()
        onChange?()
    }

    @objc private func resetTapped() {
        SharedSettings.shared.resetLook()
        configure(theme: theme, arabic: arabic)
        onChange?()
    }

    @objc private func closeTapped() { onClose?() }
}
