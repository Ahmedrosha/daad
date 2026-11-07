import Foundation

/// Word lists (bundled frequency lists + Egyptian words + what the user types) used for
/// suggestions, autocorrect, next-word prediction and glide typing.
final class Lexicon {
    static let shared = Lexicon()

    struct Entry {
        let word: String
        let normalized: String
        let count: Int
    }

    struct Candidate {
        enum Kind { case exact, completion, correction }
        let word: String
        let score: Double
        let kind: Kind
    }

    private var entries: [DaadLanguage: [Entry]] = [:]      // most frequent first
    private var counts: [DaadLanguage: [String: Int]] = [:]
    private var maxCount: [DaadLanguage: Int] = [:]
    private var learned: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    private var store: UserDefaults = .standard
    private var unsaved = 0

    private static let learnedKey = "learnedWords"
    private static let bigramsKey = "learnedBigrams"
    private static let learnedLimit = 3000
    private static let bigramLimit = 2000

    private static let englishRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let arabicRows = ["ضصثقفغعهخحج", "شسيبلاتنمكط", "ذءؤرىةوزظد"]
    private static let arabicExtra: [Character] = Array("أإآئ")
    /// Arabic words often carry these in front: و + ال + كتاب.
    private static let arabicPrefixes = ["وال", "بال", "فال", "كال", "لل", "و", "ف", "ب", "ل"]

    private static let neighbors: [Character: Set<Character>] = {
        var map: [Character: Set<Character>] = [:]
        for rows in [englishRows, arabicRows] {
            let grid = rows.map { Array($0) }
            for (r, row) in grid.enumerated() {
                for (c, ch) in row.enumerated() {
                    var set = Set<Character>()
                    for dc in [-1, 1] where row.indices.contains(c + dc) { set.insert(row[c + dc]) }
                    for dr in [-1, 1] where grid.indices.contains(r + dr) {
                        let other = grid[r + dr]
                        for dc in [-1, 0, 1] where other.indices.contains(c + dc) { set.insert(other[c + dc]) }
                    }
                    map[ch] = set
                }
            }
        }
        return map
    }()

    func configure(store: UserDefaults) {
        self.store = store
        learned = store.dictionary(forKey: Lexicon.learnedKey) as? [String: Int] ?? [:]
        bigrams = store.dictionary(forKey: Lexicon.bigramsKey) as? [String: [String: Int]] ?? [:]
    }

    // MARK: Loading

    private func ensureLoaded(_ language: DaadLanguage) {
        guard entries[language] == nil else { return }
        var list: [Entry] = []
        var map: [String: Int] = [:]
        var top = 1
        let bundle = Bundle(for: Lexicon.self)
        let name = language == .arabic ? "words_ar" : "words_en"
        if let url = bundle.url(forResource: name, withExtension: "txt"),
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
        // Everyday Egyptian words that subtitles rarely contain, ranked as fairly common.
        if language == .arabic,
           let url = bundle.url(forResource: "words_eg", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let boost = max(top / 40, 1)
            for line in text.split(whereSeparator: \.isNewline) {
                let word = line.trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty else { continue }
                if let existing = map[word] {
                    map[word] = max(existing, boost)
                } else {
                    map[word] = boost
                    list.append(Entry(word: word, normalized: Lexicon.normalize(word), count: boost))
                }
            }
            list.sort { (map[$0.word] ?? $0.count) > (map[$1.word] ?? $1.count) }
            list = list.map { Entry(word: $0.word, normalized: $0.normalized, count: map[$0.word] ?? $0.count) }
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

    // MARK: Scoring

    private func baseScore(_ word: String, language: DaadLanguage) -> Double? {
        let k = key(word)
        let uses = learned[k] ?? 0
        let count = counts[language]?[k]
        guard count != nil || uses >= 2 else { return nil }
        var score = log10(Double((count ?? 0) + 1))
        if uses > 0 { score += 1.2 * log2(Double(uses) + 1) }   // words you use win quickly
        return score
    }

    private func knownDirectly(_ word: String, language: DaadLanguage) -> Bool {
        let k = key(word)
        return counts[language]?[k] != nil || (learned[k] ?? 0) >= 2
    }

    func isKnown(_ word: String, language: DaadLanguage) -> Bool {
        ensureLoaded(language)
        if knownDirectly(word, language: language) { return true }
        if language == .arabic {
            for p in Lexicon.arabicPrefixes where word.hasPrefix(p) && word.count - p.count >= 2 {
                let rest = String(word.dropFirst(p.count))
                if knownDirectly(rest, language: language) || knownDirectly("ال" + rest, language: language) { return true }
            }
        }
        return false
    }

    /// Ranked candidates for what is being typed: the word itself (if known), completions and corrections.
    func rank(_ typed: String, language: DaadLanguage, limit: Int) -> [Candidate] {
        ensureLoaded(language)
        guard !typed.isEmpty else { return [] }
        var best: [String: Candidate] = [:]
        func add(_ word: String, _ score: Double, _ kind: Candidate.Kind) {
            let w = Lexicon.matchCase(word, like: typed)
            if let old = best[w.lowercased()], old.score >= score { return }
            best[w.lowercased()] = Candidate(word: w, score: score, kind: kind)
        }

        if isKnown(typed, language: language) {
            add(typed, (baseScore(typed, language: language) ?? 1) + 1.0, .exact)
        }
        for (word, score) in completionScores(typed, language: language) {
            add(word, score, .completion)
        }
        if language == .arabic {
            for p in Lexicon.arabicPrefixes where typed.hasPrefix(p) && typed.count - p.count >= 2 {
                let rest = String(typed.dropFirst(p.count))
                for (word, score) in completionScores(rest, language: language).prefix(5) {
                    add(p + word, score - 0.5, .completion)
                }
                break
            }
        }
        for (word, score) in correctionScores(typed, language: language) {
            add(word, score, .correction)
        }
        return Array(best.values.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func completionScores(_ prefix: String, language: DaadLanguage) -> [(String, Double)] {
        let p = Lexicon.normalize(prefix)
        let typed = key(prefix)
        guard !p.isEmpty else { return [] }
        var out: [(String, Double)] = []
        for (word, uses) in learned where uses >= 2 && word != typed && Lexicon.normalize(word).hasPrefix(p) {
            if let s = baseScore(word, language: language) {
                out.append((word, s - 0.12 * Double(word.count - prefix.count)))
            }
        }
        var found = 0
        for entry in entries[language] ?? [] where entry.normalized.hasPrefix(p) && entry.word != typed {
            let s = (baseScore(entry.word, language: language) ?? log10(Double(entry.count + 1)))
            out.append((entry.word, s - 0.12 * Double(entry.word.count - prefix.count)))
            found += 1
            if found >= 25 { break }    // list is sorted by frequency
        }
        return out
    }

    /// Words one edit away. Mistyping a neighbouring key costs less than other edits.
    private func correctionScores(_ word: String, language: DaadLanguage) -> [(String, Double)] {
        guard word.count >= 2, counts[language] != nil else { return [] }
        let chars = Array(key(word))
        let alphabet: [Character] = language == .arabic
            ? Array(Lexicon.arabicRows.joined()) + Lexicon.arabicExtra
            : Array(Lexicon.englishRows.joined())
        var found: [String: Double] = [:]

        func consider(_ candidate: [Character], penalty: Double) {
            let s = String(candidate)
            guard let base = baseScore(s, language: language) else { return }
            found[s] = max(found[s] ?? -.infinity, base - penalty)
        }

        for i in 0...chars.count {
            for c in alphabet {
                var t = chars
                t.insert(c, at: i)
                consider(t, penalty: 2.0)
            }
            guard i < chars.count else { continue }
            var d = chars
            d.remove(at: i)
            consider(d, penalty: 2.0)
            let near = Lexicon.neighbors[chars[i]] ?? []
            for c in alphabet where c != chars[i] {
                var r = chars
                r[i] = c
                consider(r, penalty: near.contains(c) ? 1.2 : 2.4)
            }
            if i + 1 < chars.count {
                var s = chars
                s.swapAt(i, i + 1)
                consider(s, penalty: 1.4)
            }
        }
        // Same word with a different hamza / taa marbuta is almost certainly what was meant.
        if language == .arabic {
            let n = Lexicon.normalize(word)
            for entry in (entries[language] ?? []).prefix(20000) where entry.normalized == n && entry.word != key(word) {
                found[entry.word] = max(found[entry.word] ?? -.infinity, log10(Double(entry.count + 1)) - 0.2)
            }
        }
        return found.map { ($0.key, $0.value) }
    }

    /// The fix autocorrect applies on space, or nil when the word looks fine.
    func autocorrection(for word: String, language: DaadLanguage) -> String? {
        guard word.count >= 2, !isKnown(word, language: language) else { return nil }
        let ranked = rank(word, language: language, limit: 3)
        guard let top = ranked.first(where: { $0.kind == .correction }), top.score > 1.0 else { return nil }
        if let first = ranked.first, first.kind == .completion, first.score > top.score + 0.8 { return nil }
        return top.word
    }

    /// Words the user tends to type after `previous`.
    func nextWords(after previous: String, limit: Int) -> [String] {
        guard let followers = bigrams[key(previous)] else { return [] }
        return followers.filter { $0.value >= 1 }.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
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

    func learn(_ word: String, after previous: String?) {
        let k = key(word)
        guard k.count >= 1, k.count <= 30, k.allSatisfy({ $0.isLetter || $0 == "'" }) else { return }
        if k.count >= 2 {
            learned[k, default: 0] += 1
            if learned.count > Lexicon.learnedLimit {
                let drop = learned.sorted { $0.value < $1.value }.prefix(learned.count - Lexicon.learnedLimit)
                for (w, _) in drop { learned[w] = nil }
            }
        }
        if let previous, !previous.isEmpty {
            let p = key(previous)
            var followers = bigrams[p] ?? [:]
            followers[k, default: 0] += 1
            if followers.count > 12, let weakest = followers.min(by: { $0.value < $1.value })?.key {
                followers[weakest] = nil
            }
            bigrams[p] = followers
            if bigrams.count > Lexicon.bigramLimit, let any = bigrams.keys.first(where: { $0 != p }) {
                bigrams[any] = nil
            }
        }
        unsaved += 1
        if unsaved >= 5 { flush() }
    }

    func flush() {
        guard unsaved > 0 else { return }
        store.set(learned, forKey: Lexicon.learnedKey)
        store.set(bigrams, forKey: Lexicon.bigramsKey)
        unsaved = 0
    }

    func clearLearned() {
        learned = [:]
        bigrams = [:]
        store.removeObject(forKey: Lexicon.learnedKey)
        store.removeObject(forKey: Lexicon.bigramsKey)
        unsaved = 0
    }
}
