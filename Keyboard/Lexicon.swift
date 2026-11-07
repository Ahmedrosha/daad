import Foundation

/// Word lists (bundled frequency lists + words the user types) used for suggestions,
/// autocorrect and glide typing.
final class Lexicon {
    static let shared = Lexicon()

    struct Entry {
        let word: String
        let normalized: String
        let count: Int
    }

    private var entries: [DaadLanguage: [Entry]] = [:]      // most frequent first
    private var counts: [DaadLanguage: [String: Int]] = [:]
    private var maxCount: [DaadLanguage: Int] = [:]
    private var learned: [String: Int] = [:]
    private var store: UserDefaults = .standard
    private var unsaved = 0

    private static let learnedKey = "learnedWords"
    private static let learnedLimit = 3000
    private static let arabicAlphabet: [Character] = Array("ابتثجحخدذرزسشصضطظعغفقكلمنهويءآأإؤئىة")
    private static let englishAlphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    func configure(store: UserDefaults) {
        self.store = store
        learned = store.dictionary(forKey: Lexicon.learnedKey) as? [String: Int] ?? [:]
    }

    // MARK: Loading

    private func ensureLoaded(_ language: DaadLanguage) {
        guard entries[language] == nil else { return }
        var list: [Entry] = []
        var map: [String: Int] = [:]
        var top = 1
        let name = language == .arabic ? "words_ar" : "words_en"
        if let url = Bundle(for: Lexicon.self).url(forResource: name, withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: " ")
                guard parts.count >= 2, let count = Int(parts[1]) else { continue }
                let word = String(parts[0])
                guard map[word] == nil else { continue }
                map[word] = count
                top = max(top, count)
                list.append(Entry(word: word, normalized: Lexicon.normalize(word), count: count))
            }
        }
        entries[language] = list
        counts[language] = map
        maxCount[language] = top
    }

    // MARK: Text helpers

    static func language(of word: String) -> DaadLanguage {
        word.contains(where: TextHelpers.isArabic) ? .arabic : .english
    }

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

    /// Copies the capitalization of what the user typed onto a suggestion.
    static func matchCase(_ word: String, like typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        if typed.count > 1 && typed == typed.uppercased() { return word.uppercased() }
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    private func key(_ word: String) -> String { word.lowercased() }

    // MARK: Queries

    func isKnown(_ word: String, language: DaadLanguage) -> Bool {
        ensureLoaded(language)
        let k = key(word)
        if counts[language]?[k] != nil { return true }
        return (learned[k] ?? 0) >= 2
    }

    /// Words that start with what the user typed, most likely first.
    func completions(for prefix: String, language: DaadLanguage, limit: Int) -> [String] {
        ensureLoaded(language)
        let p = Lexicon.normalize(prefix)
        let typed = key(prefix)
        guard !p.isEmpty else { return [] }
        var result: [String] = []

        let learnedMatches = learned
            .filter { $0.value >= 2 && $0.key != typed && Lexicon.normalize($0.key).hasPrefix(p) }
            .sorted { $0.value > $1.value }
        for (word, _) in learnedMatches.prefix(limit) { result.append(word) }

        if result.count < limit, let list = entries[language] {
            for entry in list where entry.normalized.hasPrefix(p) && entry.word != typed && !result.contains(entry.word) {
                result.append(entry.word)
                if result.count >= limit { break }
            }
        }
        return result.map { Lexicon.matchCase($0, like: prefix) }
    }

    /// Dictionary words one edit away from what the user typed, most likely first.
    func corrections(for word: String, language: DaadLanguage, limit: Int) -> [String] {
        ensureLoaded(language)
        guard let map = counts[language], word.count >= 2 else { return [] }
        let chars = Array(key(word))
        let alphabet = language == .arabic ? Lexicon.arabicAlphabet : Lexicon.englishAlphabet
        var found: [String: Int] = [:]

        func consider(_ candidate: [Character]) {
            let s = String(candidate)
            if let c = map[s] { found[s] = max(found[s] ?? 0, c) }
            if let l = learned[s], l >= 2 { found[s] = max(found[s] ?? 0, (maxCount[language] ?? 1) + l) }
        }

        for i in 0...chars.count {
            for c in alphabet {
                var t = chars
                t.insert(c, at: i)
                consider(t)
            }
            guard i < chars.count else { continue }
            var d = chars
            d.remove(at: i)
            consider(d)
            for c in alphabet where c != chars[i] {
                var r = chars
                r[i] = c
                consider(r)
            }
            if i + 1 < chars.count {
                var s = chars
                s.swapAt(i, i + 1)
                consider(s)
            }
        }
        // Same word written with different hamza / taa marbuta counts as the best correction.
        let normalizedWord = Lexicon.normalize(word)
        if let list = entries[language] {
            for entry in list.prefix(20000) where entry.normalized == normalizedWord && entry.word != key(word) {
                found[entry.word] = max(found[entry.word] ?? 0, entry.count * 4)
            }
        }
        return found.sorted { $0.value > $1.value }.prefix(limit).map { Lexicon.matchCase($0.key, like: word) }
    }

    /// Every word glide typing may produce, with how common it is.
    func glideVocabulary(_ language: DaadLanguage) -> [(word: String, count: Int)] {
        ensureLoaded(language)
        var list = (entries[language] ?? []).map { (word: $0.word, count: $0.count) }
        let top = maxCount[language] ?? 1
        for (word, uses) in learned where uses >= 2 && Lexicon.language(of: word) == language && counts[language]?[word] == nil {
            list.append((word: word, count: min(top, uses * 1000)))
        }
        return list
    }

    func topCount(_ language: DaadLanguage) -> Int {
        ensureLoaded(language)
        return maxCount[language] ?? 1
    }

    // MARK: Learning

    func learn(_ word: String) {
        let k = key(word)
        guard k.count >= 2, k.count <= 30, k.allSatisfy({ $0.isLetter || $0 == "'" }) else { return }
        learned[k, default: 0] += 1
        if learned.count > Lexicon.learnedLimit {
            let drop = learned.sorted { $0.value < $1.value }.prefix(learned.count - Lexicon.learnedLimit)
            for (w, _) in drop { learned[w] = nil }
        }
        unsaved += 1
        if unsaved >= 5 { flush() }
    }

    func flush() {
        guard unsaved > 0 else { return }
        store.set(learned, forKey: Lexicon.learnedKey)
        unsaved = 0
    }

    func clearLearned() {
        learned = [:]
        store.removeObject(forKey: Lexicon.learnedKey)
        unsaved = 0
    }
}
