import Foundation

/// Every on/off option shown in the app's Settings screen and read by the keyboard.
enum DaadSetting: String, CaseIterable {
    case numberRow       // صف الأرقام
    case arabicDigits    // ١٢٣ بدل 123 في الكيبورد العربي
    case autoCapitalize  // حرف كابيتال أول الجملة
    case quickPeriod     // ضغطتين على المسافة = نقطة
    case keySound        // صوت الضغط
    case haptics         // اهتزاز الضغط
    case keyPopups       // معاينة الحرف
    case rtlMark         // علامة اتجاه مخفية أول النص العربي
    case suggestions     // شريط الاقتراحات
    case autocorrect     // التصحيح التلقائي
    case glideTyping     // الكتابة بالسحب
    case blockOffensive  // منع الكلمات البذيئة من الاقتراحات
    case emojiSuggestions // اقتراح إيموجي
    case arrowRow        // صف أسهم تحريك المؤشر
    case franco          // فرانكو ← عربي
    case swipeUpSymbols  // رموز بالسحب لفوق على الحروف
    case harakatOnHold   // التشكيل بالضغط المطوّل
    case splitLandscape  // كيبورد مقسوم في الوضع العرضي
    case autoLanguage    // يختار اللغة حسب الكلمة اللي قبل المؤشر

    var defaultValue: Bool {
        switch self {
        case .rtlMark, .autocorrect, .arrowRow: return false
        default: return true
        }
    }
}

enum DaadLanguage: String {
    case arabic = "ar"
    case english = "en"

    var toggled: DaadLanguage { self == .arabic ? .english : .arabic }
    var displayName: String { self == .arabic ? "العربية" : "English" }
}

/// The keyboards you switch between: Arabic, English, or both at once (Arabic keys, English by flicking down).
enum InputMode: String, CaseIterable {
    case arabic = "ar"
    case english = "en"
    case dual = "dual"

    /// The language the keys are laid out in.
    var language: DaadLanguage { self == .english ? .english : .arabic }

    /// Label on the language button in the bar.
    var shortLabel: String {
        switch self {
        case .arabic: return "ع"
        case .english: return "En"
        case .dual: return "ع+En"
        }
    }

    var displayName: String {
        switch self {
        case .arabic: return "العربية"
        case .english: return "English"
        case .dual: return "العربية + English"
        }
    }

    /// The next (or previous) mode among the enabled ones, in the order Arabic → English → both.
    func step(_ forward: Bool, enabled: [InputMode]) -> InputMode {
        let order = InputMode.allCases.filter { enabled.contains($0) || $0 == self }
        guard let i = order.firstIndex(of: self), order.count > 1 else { return self }
        return order[(i + (forward ? 1 : order.count - 1)) % order.count]
    }
}

/// Buttons in the bar above the keys (besides hide and language, which stay put on the left).
enum BarItem: String, CaseIterable {
    case emoji, calculator, gif, clipboard, paste, arrows, copyAll, deleteAll, tools

    var arabicTitle: String {
        switch self {
        case .emoji: return "إيموجي"
        case .calculator: return "آلة حاسبة"
        case .gif: return "GIF"
        case .clipboard: return "الحافظة"
        case .paste: return "لصق"
        case .arrows: return "صف الأسهم"
        case .copyAll: return "نسخ الكل"
        case .deleteAll: return "مسح الكل"
        case .tools: return "كل الأدوات"
        }
    }

    var englishTitle: String {
        switch self {
        case .emoji: return "Emoji"
        case .calculator: return "Calculator"
        case .gif: return "GIF"
        case .clipboard: return "Clipboard"
        case .paste: return "Paste"
        case .arrows: return "Arrow row"
        case .copyAll: return "Copy all"
        case .deleteAll: return "Delete all"
        case .tools: return "All tools"
        }
    }

    /// SF Symbol for the button (nil: drawn specially, like GIF and the calculator).
    var symbol: String? {
        switch self {
        case .emoji: return "face.smiling"
        case .calculator, .gif: return nil
        case .clipboard: return "list.bullet.clipboard"
        case .paste: return "doc.on.clipboard"
        case .arrows: return "arrow.up.and.down.and.arrow.left.and.right"
        case .copyAll: return "doc.on.doc.fill"
        case .deleteAll: return "trash"
        case .tools: return "square.grid.2x2"
        }
    }
}

/// Settings shared between the app and the keyboard through the App Group.
final class SharedSettings {
    static let appGroupID = "group.com.daad.keyboard"
    static let store: UserDefaults? = UserDefaults(suiteName: appGroupID)
    static let shared = SharedSettings()

    private let defaults: UserDefaults

    private init() {
        defaults = SharedSettings.store ?? .standard
        var initial: [String: Any] = [:]
        for setting in DaadSetting.allCases { initial[setting.rawValue] = setting.defaultValue }
        initial[Keys.language] = DaadLanguage.arabic.rawValue
        defaults.register(defaults: initial)
    }

    private enum Keys {
        static let language = "language"
        static let inputMode = "inputMode"
        static let barOrder = "barItemOrder"
        static let barHidden = "barItemsHidden"
        static let enabledModes = "enabledInputModes"
        static let clearLearned = "clearLearnedRequested"
        static let shortcuts = "textShortcuts"
        static let shortcutsSeeded = "textShortcutsSeeded"
        static let pinned = "pinnedTexts"
        static let oneHanded = "oneHandedMode"
        static let letterScale = "letterFontScale"
        static let numberScale = "numberFontScale"
        static let keyHeight = "keyHeight"
        static let widthScale = "keyboardWidthScale"
        static let font = "keyFont"
        static let arabicLayout = "arabicLayout"
        static let theme = "keyboardTheme"
        static let sound = "keySoundStyle"
        static let haptic = "hapticStyle"
    }

    /// "system", "light", "dark", "ocean", "forest", "purple", "sand" or "photo".
    var keyboardTheme: String {
        get { defaults.string(forKey: Keys.theme) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.theme) }
    }

    /// "classic", "tink", "tock" or "soft".
    var keySoundStyle: String {
        get { defaults.string(forKey: Keys.sound) ?? "classic" }
        set { defaults.set(newValue, forKey: Keys.sound) }
    }

    /// "light", "medium", "heavy", "soft" or "rigid".
    var hapticStyle: String {
        get { defaults.string(forKey: Keys.haptic) ?? "light" }
        set { defaults.set(newValue, forKey: Keys.haptic) }
    }

    /// Photo chosen in the app as the keyboard background (shared through the App Group).
    static var backgroundImageURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("keyboard-background.jpg")
    }

    /// Arabic letter arrangement: "iphone" (like Apple's keyboard) or "gboard".
    var arabicLayout: String {
        get { defaults.string(forKey: Keys.arabicLayout) ?? "iphone" }
        set { defaults.set(newValue, forKey: Keys.arabicLayout) }
    }

    // MARK: Look & size

    private func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }

    /// Size of letters on the keys (0.7 – 1.4).
    var letterFontScale: Double {
        get { double(Keys.letterScale, 1) }
        set { defaults.set(newValue, forKey: Keys.letterScale) }
    }

    /// Size of digits on the keys (0.7 – 1.4).
    var numberFontScale: Double {
        get { double(Keys.numberScale, 1) }
        set { defaults.set(newValue, forKey: Keys.numberScale) }
    }

    /// Height of one row of keys in points (40 – 64).
    var keyHeight: Double {
        get { double(Keys.keyHeight, 52) }
        set { defaults.set(newValue, forKey: Keys.keyHeight) }
    }

    /// Width of the keyboard compared to the screen (0.7 – 1).
    var keyboardWidthScale: Double {
        get { double(Keys.widthScale, 1) }
        set { defaults.set(newValue, forKey: Keys.widthScale) }
    }

    /// Font id for key letters, see KeyFont.
    var keyFont: String {
        get { defaults.string(forKey: Keys.font) ?? "system" }
        set { defaults.set(newValue, forKey: Keys.font) }
    }

    func resetLook() {
        for k in [Keys.letterScale, Keys.numberScale, Keys.keyHeight, Keys.widthScale, Keys.font] {
            defaults.removeObject(forKey: k)
        }
    }

    /// "off", "left" or "right": the keyboard shrinks toward one side.
    var oneHandedMode: String {
        get { defaults.string(forKey: Keys.oneHanded) ?? "off" }
        set { defaults.set(newValue, forKey: Keys.oneHanded) }
    }

    static let defaultShortcuts: [String: String] = [
        "omw": "on my way",
        "brb": "be right back",
        "idk": "I don't know",
        "thx": "thanks",
        "انشا": "إن شاء الله",
        "ماشا": "ما شاء الله",
        "سلامو": "السلام عليكم ورحمة الله وبركاته",
        "جزك": "جزاك الله خيرًا",
        "حمدلله": "الحمد لله",
    ]

    /// Typed shortcut → text it becomes ("omw" → "on my way"). Seeded with examples once.
    var shortcuts: [String: String] {
        get {
            if !defaults.bool(forKey: Keys.shortcutsSeeded) {
                defaults.set(SharedSettings.defaultShortcuts, forKey: Keys.shortcuts)
                defaults.set(true, forKey: Keys.shortcutsSeeded)
            }
            return defaults.dictionary(forKey: Keys.shortcuts) as? [String: String] ?? [:]
        }
        set { defaults.set(newValue, forKey: Keys.shortcuts) }
    }

    /// Texts pinned in the clipboard; always shown at the top.
    var pinnedTexts: [String] {
        get { defaults.stringArray(forKey: Keys.pinned) ?? [] }
        set { defaults.set(newValue, forKey: Keys.pinned) }
    }

    /// The app asks the keyboard to forget learned words (the keyboard owns that data).
    func requestClearLearned() { defaults.set(true, forKey: Keys.clearLearned) }

    func consumeClearLearnedRequest() -> Bool {
        guard defaults.bool(forKey: Keys.clearLearned) else { return false }
        defaults.set(false, forKey: Keys.clearLearned)
        return true
    }

    func bool(_ setting: DaadSetting) -> Bool { defaults.bool(forKey: setting.rawValue) }

    func set(_ value: Bool, for setting: DaadSetting) { defaults.set(value, forKey: setting.rawValue) }

    var language: DaadLanguage {
        get { DaadLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .arabic }
        set { defaults.set(newValue.rawValue, forKey: Keys.language) }
    }

    /// Every bar button in the user's order (new buttons from updates go at the end).
    var barOrder: [BarItem] {
        get {
            let saved = (defaults.stringArray(forKey: Keys.barOrder) ?? []).compactMap(BarItem.init(rawValue:))
            return saved + BarItem.allCases.filter { !saved.contains($0) }
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Keys.barOrder) }
    }

    var barHidden: Set<BarItem> {
        get { Set((defaults.stringArray(forKey: Keys.barHidden) ?? []).compactMap(BarItem.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue), forKey: Keys.barHidden) }
    }

    /// The bar buttons to show, left to right.
    var barItems: [BarItem] { barOrder.filter { !barHidden.contains($0) } }

    /// The keyboard last used: Arabic, English or both.
    var inputMode: InputMode {
        get { InputMode(rawValue: defaults.string(forKey: Keys.inputMode) ?? "") ?? (language == .english ? .english : .arabic) }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.inputMode)
            language = newValue.language
        }
    }

    /// Keyboards included when switching (all three unless the user turned some off; never empty).
    var enabledModes: [InputMode] {
        get {
            let saved = (defaults.stringArray(forKey: Keys.enabledModes) ?? InputMode.allCases.map(\.rawValue))
                .compactMap(InputMode.init(rawValue:))
            return saved.isEmpty ? [.arabic] : InputMode.allCases.filter(saved.contains)
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Keys.enabledModes) }
    }
}
