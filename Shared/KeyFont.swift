import UIKit

/// Fonts offered for the letters on the keys. Names that iOS doesn't have fall back to the system font.
enum KeyFont: String, CaseIterable {
    case system, rounded, serif, naskh, nile, farah, baghdad, damascus, mishafi

    var title: String {
        switch self {
        case .system: return "افتراضي"
        case .rounded: return "مستدير"
        case .serif: return "Serif"
        case .naskh: return "نسخ"
        case .nile: return "النيل"
        case .farah: return "فرح"
        case .baghdad: return "بغداد"
        case .damascus: return "دمشق"
        case .mishafi: return "ديواني"
        }
    }

    func font(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        switch self {
        case .system:
            return base
        case .rounded:
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        case .serif:
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        case .naskh: return UIFont(name: "DecoTypeNaskh", size: size) ?? base
        case .nile: return UIFont(name: "AlNile", size: size) ?? base
        case .farah: return UIFont(name: "Farah", size: size) ?? base
        case .baghdad: return UIFont(name: "Baghdad", size: size) ?? base
        case .damascus: return UIFont(name: "Damascus", size: size) ?? base
        case .mishafi: return UIFont(name: "DiwanMishafi", size: size) ?? base
        }
    }
}

/// How key labels are drawn (font and sizes chosen by the user).
struct KeyLook: Equatable {
    var font: KeyFont = .system
    var letterScale: CGFloat = 1
    var numberScale: CGFloat = 1

    static var current: KeyLook {
        let s = SharedSettings.shared
        return KeyLook(font: KeyFont(rawValue: s.keyFont) ?? .system,
                       letterScale: CGFloat(s.letterFontScale),
                       numberScale: CGFloat(s.numberFontScale))
    }
}
