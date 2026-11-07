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

    var defaultValue: Bool {
        switch self {
        case .rtlMark: return false
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

    private enum Keys { static let language = "language" }

    func bool(_ setting: DaadSetting) -> Bool { defaults.bool(forKey: setting.rawValue) }

    func set(_ value: Bool, for setting: DaadSetting) { defaults.set(value, forKey: setting.rawValue) }

    var language: DaadLanguage {
        get { DaadLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .arabic }
        set { defaults.set(newValue.rawValue, forKey: Keys.language) }
    }
}
