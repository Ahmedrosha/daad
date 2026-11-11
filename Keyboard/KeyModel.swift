import UIKit

enum KeyboardMode: Equatable {
    case letters
    case symbols1
    case symbols2
}

enum ShiftState: Equatable {
    case off
    case on
    case locked
}

enum ArrowDirection: Equatable {
    case left, right, up, down
}

enum KeyAction: Equatable {
    case character(String)
    case backspace
    case forwardDelete
    case shift
    case space
    case returnKey
    case nextKeyboard
    case dismiss
    case emoji
    case arrow(ArrowDirection)
    case modeChange(KeyboardMode)

    var isCharacter: Bool {
        if case .character = self { return true }
        return false
    }
}

enum KeyStyle {
    case normal
    case special
    case accent
}

struct Key {
    var action: KeyAction
    var label: String
    var symbol: String? = nil
    var alternates: [String] = []
    var width: CGFloat = 1
    var style: KeyStyle = .normal
    var smallLabel: Bool = false
    /// Typed by flicking up on the key (shown small in the corner).
    var upChar: String? = nil
    /// Typed by flicking down on the key (dual keyboard: the English letter, shown small top-left).
    var downChar: String? = nil
}

struct KeyRow {
    var keys: [Key]
    var rightToLeft: Bool
}

enum TextHelpers {
    /// Harakat and other combining marks are shown on a tatweel so they are visible on a key.
    static func display(_ text: String) -> String {
        guard let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1 else { return text }
        if scalar.properties.generalCategory == .nonspacingMark { return "ـ" + text }
        return text
    }

    static func isArabic(_ c: Character) -> Bool {
        for scalar in c.unicodeScalars {
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
                return true
            default:
                continue
            }
        }
        return false
    }
}
