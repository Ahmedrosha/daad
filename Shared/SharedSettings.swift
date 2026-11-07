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

    var defaultValue: Bool {
        switch self {
        case .rtlMark, .autocorrect: return false
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
        static let clearLearned = "clearLearnedRequested"
        static let shortcuts = "textShortcuts"
        static let shortcutsSeeded = "textShortcutsSeeded"
        static let pinned = "pinnedTexts"
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
}
