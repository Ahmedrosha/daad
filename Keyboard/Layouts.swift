import UIKit

struct LayoutContext: Equatable {
    var language: DaadLanguage
    var mode: KeyboardMode
    var shift: ShiftState
    var showNumberRow: Bool
    var arabicDigits: Bool
    var needsGlobe: Bool
    var returnLabel: String   // "" = return arrow icon
    var dark: Bool
}

enum Layouts {
    static let arabicDigits = ["١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩", "٠"]
    static let latinDigits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static let harakat = ["َ", "ُ", "ِ", "ّ", "ْ", "ً", "ٌ", "ٍ"]

    static let arabicAlternates: [String: [String]] = [
        "ا": ["أ", "إ", "آ", "ٱ"],
        "ي": ["ئ", "ى"],
        "ى": ["ئ", "ي"],
        "و": ["ؤ"],
        "ء": ["ئ", "ؤ", "أ", "إ"],
        "ه": ["ة"],
        "ة": ["ه"],
        "ل": ["لا", "لأ", "لإ", "لآ"],
        "ك": ["گ"],
        "ف": ["ڤ"],
        "ج": ["چ"],
        "ب": ["پ"],
    ]

    static let englishAlternates: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å"],
        "e": ["è", "é", "ê", "ë", "ē"],
        "i": ["ì", "í", "î", "ï"],
        "o": ["ò", "ó", "ô", "ö", "õ", "ø", "œ"],
        "u": ["ù", "ú", "û", "ü"],
        "c": ["ç"],
        "n": ["ñ"],
        "s": ["ß"],
        "y": ["ÿ"],
    ]

    static func build(_ c: LayoutContext) -> (rows: [KeyRow], maxUnits: CGFloat) {
        switch c.mode {
        case .letters:
            return c.language == .arabic ? arabicLetters(c) : englishLetters(c)
        case .symbols1, .symbols2:
            return (symbols(c), 10)
        }
    }

    // MARK: Letters

    private static func arabicLetters(_ c: LayoutContext) -> ([KeyRow], CGFloat) {
        let max: CGFloat = 11
        var rows: [KeyRow] = []
        if c.showNumberRow { rows.append(numberRow(c, maxUnits: max)) }
        let r1 = ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج"]
        let r2 = ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"]
        let r3 = ["ذ", "ء", "ؤ", "ر", "ى", "ة", "و", "ز", "ظ", "د"]
        rows.append(KeyRow(keys: chars(r1, alternates: arabicAlternates), rightToLeft: false))
        rows.append(KeyRow(keys: chars(r2, alternates: arabicAlternates), rightToLeft: false))
        // Standard Arabic layout: ض on the far left (where Q is), delete on the far right.
        rows.append(KeyRow(keys: chars(r3, alternates: arabicAlternates) + [backspace(width: 1)], rightToLeft: false))
        let comma = Key(action: .character("،"), label: "،", alternates: harakat + ["؛"])
        let period = Key(action: .character("."), label: ".", alternates: ["؟", "!", "،", ":", "\"", "-", "'"])
        rows.append(bottomRow(c, maxUnits: max,
                              modeKey: modeKey("١٢٣", to: .symbols1),
                              left: comma, right: period))
        return (rows, max)
    }

    private static func englishLetters(_ c: LayoutContext) -> ([KeyRow], CGFloat) {
        let max: CGFloat = 10
        let upper = c.shift != .off
        var rows: [KeyRow] = []
        if c.showNumberRow { rows.append(numberRow(c, maxUnits: max)) }
        let r1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
        let r2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
        let r3 = ["z", "x", "c", "v", "b", "n", "m"]
        rows.append(KeyRow(keys: chars(r1, alternates: englishAlternates, upper: upper), rightToLeft: false))
        rows.append(KeyRow(keys: chars(r2, alternates: englishAlternates, upper: upper), rightToLeft: false))
        let shiftSymbol: String
        switch c.shift {
        case .off: shiftSymbol = "shift"
        case .on: shiftSymbol = "shift.fill"
        case .locked: shiftSymbol = "capslock.fill"
        }
        let shift = Key(action: .shift, label: "", symbol: shiftSymbol, width: 1.5,
                        style: c.shift == .off ? .special : .normal)
        rows.append(KeyRow(keys: [shift] + chars(r3, alternates: englishAlternates, upper: upper) + [backspace(width: 1.5)],
                           rightToLeft: false))
        let comma = Key(action: .character(","), label: ",", alternates: [";", ":", "'", "\""])
        let period = Key(action: .character("."), label: ".", alternates: ["?", "!", ",", "'", "\"", "-", ":"])
        rows.append(bottomRow(c, maxUnits: max, modeKey: modeKey("123", to: .symbols1), left: comma, right: period))
        return (rows, max)
    }

    private static func numberRow(_ c: LayoutContext, maxUnits: CGFloat) -> KeyRow {
        let useArabic = c.language == .arabic && c.arabicDigits
        let primary = useArabic ? arabicDigits : latinDigits
        let other = useArabic ? latinDigits : arabicDigits
        let width = maxUnits / 10
        let keys = primary.indices.map { i in
            Key(action: .character(primary[i]), label: primary[i], alternates: [other[i]], width: width)
        }
        return KeyRow(keys: keys, rightToLeft: false)
    }

    // MARK: Symbols

    private static func symbols(_ c: LayoutContext) -> [KeyRow] {
        let arabic = c.language == .arabic
        var rows: [KeyRow] = []
        let r3Chars = arabic ? [".", "،", "؟", "!", "'"] : [".", ",", "?", "!", "'"]
        let r3Keys = r3Chars.map { Key(action: .character($0), label: $0, width: 1.4) }

        if c.mode == .symbols1 {
            let digits = (arabic && c.arabicDigits) ? arabicDigits : latinDigits
            let otherDigits = (arabic && c.arabicDigits) ? latinDigits : arabicDigits
            rows.append(KeyRow(keys: digits.indices.map {
                Key(action: .character(digits[$0]), label: digits[$0], alternates: [otherDigits[$0]])
            }, rightToLeft: false))
            let r2 = arabic
                ? ["-", "/", ":", "؛", "(", ")", "$", "&", "@", "\""]
                : ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
            rows.append(KeyRow(keys: chars(r2), rightToLeft: false))
            let more = Key(action: .modeChange(.symbols2), label: "#+=", width: 1.5, style: .special, smallLabel: true)
            rows.append(KeyRow(keys: [more] + r3Keys + [backspace(width: 1.5)], rightToLeft: false))
        } else {
            let r1 = arabic
                ? ["[", "]", "{", "}", "#", "%", "«", "»", "+", "="]
                : ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
            rows.append(KeyRow(keys: chars(r1), rightToLeft: false))
            if arabic {
                let marks = harakat + ["ـ", "~"]
                rows.append(KeyRow(keys: marks.map {
                    Key(action: .character($0), label: TextHelpers.display($0))
                }, rightToLeft: false))
            } else {
                rows.append(KeyRow(keys: chars(["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]), rightToLeft: false))
            }
            let back = Key(action: .modeChange(.symbols1), label: arabic ? "١٢٣" : "123",
                           width: 1.5, style: .special, smallLabel: true)
            rows.append(KeyRow(keys: [back] + r3Keys + [backspace(width: 1.5)], rightToLeft: false))
        }
        rows.append(bottomRow(c, maxUnits: 10,
                              modeKey: modeKey(arabic ? "أبج" : "ABC", to: .letters),
                              left: nil, right: nil))
        return rows
    }

    // MARK: Building blocks

    private static func chars(_ list: [String], alternates: [String: [String]] = [:], upper: Bool = false) -> [Key] {
        list.map { base in
            let value = upper ? base.uppercased() : base
            let alts = (alternates[base] ?? []).map { upper ? $0.uppercased() : $0 }
            return Key(action: .character(value), label: value, alternates: alts)
        }
    }

    private static func backspace(width: CGFloat) -> Key {
        Key(action: .backspace, label: "", symbol: "delete.left", width: width, style: .special)
    }

    private static func modeKey(_ label: String, to mode: KeyboardMode) -> Key {
        Key(action: .modeChange(mode), label: label, width: 1.5, style: .special, smallLabel: true)
    }

    private static func bottomRow(_ c: LayoutContext, maxUnits: CGFloat, modeKey: Key, left: Key?, right: Key?) -> KeyRow {
        var keys: [Key] = [modeKey]
        if c.needsGlobe {
            keys.append(Key(action: .nextKeyboard, label: "", symbol: "globe", width: 1.2, style: .special))
        }
        keys.append(Key(action: .dismiss, label: "", symbol: "keyboard.chevron.compact.down", width: 1.2, style: .special))
        if let left { keys.append(left) }
        let spaceIndex = keys.count
        keys.append(Key(action: .space, label: c.language.displayName, smallLabel: true))
        if let right { keys.append(right) }
        let isAccent = !c.returnLabel.isEmpty
        keys.append(Key(action: .returnKey, label: c.returnLabel,
                        symbol: isAccent ? nil : "return",
                        width: 2, style: isAccent ? .accent : .special, smallLabel: true))
        let used = keys.enumerated().reduce(CGFloat(0)) { $0 + ($1.offset == spaceIndex ? 0 : $1.element.width) }
        keys[spaceIndex].width = Swift.max(2, maxUnits - used)
        return KeyRow(keys: keys, rightToLeft: false)
    }
}
