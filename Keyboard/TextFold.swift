import Foundation

/// Text folding shared by the keyboard and the build-time dictionary tool (scripts/dictgen), so both
/// fold words exactly the same way. Foundation only.
enum TextFold {
    /// Loose form used for matching: lowercase, no harakat, hamza/taa marbuta variants folded.
    static func normalize(_ text: String) -> String {
        var out = ""
        for scalar in text.lowercased().unicodeScalars {
            switch scalar.value {
            case 0x064B...0x0652, 0x0640: continue           // harakat, tatweel
            case 0x0623, 0x0625, 0x0622, 0x0671: out.append("ا")
            case 0x0649: out.append("ي")
            case 0x0629: out.append("ه")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// The keys a word is typed with (glide typing): lowercase, hamza seats folded, no harakat.
    static func keyLetters(of word: String) -> [Character] {
        var out: [Character] = []
        for ch in word.lowercased() {
            switch ch {
            case "أ", "إ", "آ", "ٱ": out.append("ا")
            case "ئ": out.append("ي")
            case "\u{064B}", "\u{064C}", "\u{064D}", "\u{064E}", "\u{064F}", "\u{0650}", "\u{0651}", "\u{0652}", "ـ":
                continue
            default: out.append(ch)
            }
        }
        return out
    }
}
