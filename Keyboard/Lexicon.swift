import Foundation

/// Word lists (bundled frequency lists + Egyptian words + what the user types) used for
/// suggestions, autocorrect, next-word prediction and glide typing.
final class Lexicon {
    static let shared = Lexicon()

    struct Candidate {
        enum Kind { case exact, completion, correction }
        let word: String
        let score: Double
        let kind: Kind
    }

    /// Bundled words, packed (see WordStore.swift), most frequent first.
    private var lists: [DaadLanguage: WordList] = [:]
    private var learned: [String: Int] = [:]
    private var bigrams: [String: [String: Int]] = [:]
    /// Bundled next-word tables: context ("word", "w1 w2" or "<s>") → likely next words, best first.
    private var nextTables: [DaadLanguage: [PhraseTable]] = [:]
    private var store: UserDefaults = .standard
    private var unsaved = 0
    /// Keeps rude words out of suggestions (they can still be typed).
    var blockOffensive = true

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

    /// `other`: the keyboard's own storage, used while Full Access was off. With Full Access on, the
    /// words learned there are merged in, so turning Full Access on or off doesn't lose any.
    func configure(store: UserDefaults, mergingFrom other: UserDefaults? = nil) {
        self.store = store
        invalidateCache()
        learned = store.dictionary(forKey: Lexicon.learnedKey) as? [String: Int] ?? [:]
        bigrams = store.dictionary(forKey: Lexicon.bigramsKey) as? [String: [String: Int]] ?? [:]
        guard let other, other !== store else { return }
        let otherLearned = other.dictionary(forKey: Lexicon.learnedKey) as? [String: Int] ?? [:]
        let otherBigrams = other.dictionary(forKey: Lexicon.bigramsKey) as? [String: [String: Int]] ?? [:]
        guard !otherLearned.isEmpty || !otherBigrams.isEmpty else { return }
        for (w, n) in otherLearned { learned[w] = max(learned[w] ?? 0, n) }
        for (p, followers) in otherBigrams {
            var merged = bigrams[p] ?? [:]
            for (w, n) in followers { merged[w] = max(merged[w] ?? 0, n) }
            bigrams[p] = merged
        }
        if learned.count > Lexicon.learnedLimit {
            let drop = learned.sorted { $0.value < $1.value }.prefix(learned.count - Lexicon.learnedLimit)
            for (w, _) in drop { learned[w] = nil }
        }
        store.set(learned, forKey: Lexicon.learnedKey)
        store.set(bigrams, forKey: Lexicon.bigramsKey)
        // Keep the other copy too: if Full Access is turned off again, the keyboard reads that one.
        other.set(learned, forKey: Lexicon.learnedKey)
        other.set(bigrams, forKey: Lexicon.bigramsKey)
    }

    /// The user undid an autocorrect: treat what they typed as a real word from now on.
    func keep(_ word: String) {
        let k = key(word)
        guard k.count >= 2, k.count <= 30 else { return }
        learned[k] = max(learned[k] ?? 0, 2)   // 2 = known, so it isn't "fixed" again
        invalidateCache()
        unsaved += 1
        flush()
    }

    // MARK: Loading

    private func ensureLoaded(_ language: DaadLanguage) {
        guard lists[language] == nil else { return }
        lists[language] = Lexicon.loadWords(language)
        invalidateCache()
    }

    private var preloading: Set<DaadLanguage> = []

    /// Reads a word list on a background thread so the first letter typed doesn't wait for it
    /// (the Arabic list has 100,000 words). Call on the main thread; results are stored on it too.
    func preload(_ language: DaadLanguage) {
        preloadNextTables(language)
        guard lists[language] == nil, !preloading.contains(language) else { return }
        preloading.insert(language)
        DispatchQueue.global(qos: .userInitiated).async {
            let list = Lexicon.loadWords(language)
            DispatchQueue.main.async {
                self.preloading.remove(language)
                guard self.lists[language] == nil else { return }   // typing already loaded it
                self.lists[language] = list
                self.invalidateCache()
            }
        }
    }

    /// Low memory: let go of what can be read again later (the other language's words, the Franco
    /// index and the next-word tables). Learned words stay.
    func trim(keeping languages: Set<DaadLanguage>) {
        for lang in [DaadLanguage.arabic, .english] where !languages.contains(lang) {
            lists[lang] = nil
        }
        invalidateCache()
        francoIndex = nil
        nextTables = [:]
    }

    private static func loadWords(_ language: DaadLanguage) -> WordList {
        let bundle = Bundle(for: Lexicon.self)
        let name = language == .arabic ? "words_ar" : "words_en"
        let list = WordList(file: bundle.url(forResource: name, withExtension: "txt"),
                            expected: language == .arabic ? 105_000 : 50_000)
        // Everyday Egyptian words that subtitles rarely contain, ranked as fairly common.
        // "word" = everyday word, ranked high; "word 3" = a generated verb form, ranked a bit lower.
        if language == .arabic {
            let top = list.top
            list.merge(file: bundle.url(forResource: "words_eg", withExtension: "txt")) { tier in
                max(top / (40 * tier), 1)
            }
            list.sortByCount()
        }
        list.buildIndexes()
        return list
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
        let count = lists[language]?.count(of: k)
        guard count != nil || uses >= 2 else { return nil }
        var score = log10(Double((count ?? 0) + 1))
        if uses > 0 { score += 1.2 * log2(Double(uses) + 1) }   // words you use win quickly
        return score
    }

    private func knownDirectly(_ word: String, language: DaadLanguage) -> Bool {
        let k = key(word)
        return lists[language]?.count(of: k) != nil || (learned[k] ?? 0) >= 2
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
    func rank(_ typed: String, language: DaadLanguage, limit: Int,
              previous: String? = nil, beforePrevious: String? = nil) -> [Candidate] {
        ensureLoaded(language)
        guard !typed.isEmpty else { return [] }
        // The same question is asked several times per key (suggestions, autocorrect, the app's echo).
        let cacheKey = "\(typed)\u{1}\(language == .arabic ? "a" : "e")\u{1}\(limit)\u{1}\(previous ?? "")\u{1}\(beforePrevious ?? "")\u{1}\(blockOffensive)"
        if let hit = rankCache[cacheKey] { return hit }
        let result = computeRank(typed, language: language, limit: limit, previous: previous, beforePrevious: beforePrevious)
        if rankCache.count >= 24 { rankCache.removeAll(keepingCapacity: true) }
        rankCache[cacheKey] = result
        return result
    }

    private var rankCache: [String: [Candidate]] = [:]
    /// Learned words with their loose form, rebuilt only after something is learned.
    private var learnedForms: [(word: String, form: String)]?

    private func invalidateCache() {
        rankCache.removeAll(keepingCapacity: true)
        learnedForms = nil
    }

    private func computeRank(_ typed: String, language: DaadLanguage, limit: Int,
                             previous: String?, beforePrevious: String?) -> [Candidate] {
        // Words that fit after the previous words get a lift (e.g. "how are y…" → "you").
        let context = contextScores(previous: previous, beforePrevious: beforePrevious, language: language)
        var best: [String: Candidate] = [:]
        func add(_ word: String, _ rawScore: Double, _ kind: Candidate.Kind) {
            if blockOffensive && kind != .exact && WordExtras.isBlocked(word) { return }
            let score = rawScore + 0.5 * (context[tableKey(word)] ?? 0)
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
        var sorted = best.values.sorted { $0.score > $1.score }
        // A word the dictionary doesn't know is often a typo ("خاصت" → "خلصت"): longer words that start
        // the same can outscore the fix, so keep the best correction among the first two guesses.
        if !sorted.contains(where: { $0.kind == .exact }),
           let i = sorted.firstIndex(where: { $0.kind == .correction }), i >= 2 {
            let fix = sorted.remove(at: i)
            sorted.insert(fix, at: 1)
        }
        return Array(sorted.prefix(limit))
    }

    private func completionScores(_ prefix: String, language: DaadLanguage) -> [(String, Double)] {
        let p = Lexicon.normalize(prefix)
        let typed = key(prefix)
        guard !p.isEmpty else { return [] }
        var out: [(String, Double)] = []
        if learnedForms == nil {
            learnedForms = learned.filter { $0.value >= 2 }.map { (word: $0.key, form: Lexicon.normalize($0.key)) }
        }
        for (word, form) in learnedForms ?? [] where word != typed && form.hasPrefix(p) {
            if let s = baseScore(word, language: language) {
                out.append((word, s - 0.12 * Double(word.count - prefix.count)))
            }
        }
        guard let list = lists[language] else { return out }
        // The 25 most frequent words that start this way (26 asked for: one may be the typed word itself).
        var found = 0
        for i in list.indexes(withPrefix: p, limit: 26) {
            let word = list.word(i)
            guard word != typed else { continue }
            let s = (baseScore(word, language: language) ?? log10(Double(list.count(at: i) + 1)))
            out.append((word, s - 0.12 * Double(word.count - prefix.count)))
            found += 1
            if found >= 25 { break }
        }
        return out
    }

    /// Words one edit away. Mistyping a neighbouring key costs less than other edits.
    private func correctionScores(_ word: String, language: DaadLanguage) -> [(String, Double)] {
        guard word.count >= 2, lists[language] != nil else { return [] }
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
            if let list = lists[language] {
                for i in list.indexes(withNormalized: Lexicon.normalize(word)) where i < 20000 {
                    let w = list.word(i)
                    guard w != key(word) else { continue }
                    found[w] = max(found[w] ?? -.infinity, log10(Double(list.count(at: i) + 1)) - 0.2)
                }
            }
        }
        return found.map { ($0.key, $0.value) }
    }

    /// The fix autocorrect applies on space, or nil when the word looks fine.
    func autocorrection(for word: String, language: DaadLanguage) -> String? {
        guard word.count >= 2, !isKnown(word, language: language) else { return nil }
        if language == .arabic, Lexicon.leavesEgyptianForms, isEgyptianForm(word) { return nil }
        let ranked = rank(word, language: language, limit: 3)
        guard let top = ranked.first(where: { $0.kind == .correction }), top.score > 1.0 else { return nil }
        if let first = ranked.first, first.kind == .completion, first.score > top.score + 0.8 { return nil }
        return top.word
    }

    /// Off only in tests, to compare.
    static var leavesEgyptianForms = true

    private static let egyptianLeading = ["و", "ف"]
    private static let egyptianPrefixes = ["ه", "ح", "ب", "م", "ما", "ل"]
    private static let egyptianEndings = ["ها", "هم", "هوم", "كم", "نا", "ني", "لي", "لك", "له", "لها", "لهم", "لنا", "ك", "ي", "ه", "و"]

    /// An Egyptian word the dictionary doesn't hold whole: a known word with the bits colloquial speech
    /// adds around it ("هعملها" = ه + عملها, "متزعلش" = م + تزعل + ش, "عيالي" = عيال + ي).
    /// Autocorrect leaves these alone; suggestions still show.
    private func isEgyptianForm(_ word: String) -> Bool {
        // Short stems match too easily (a typo that happens to end in "ه" over a 2-letter word).
        func known(_ stem: String) -> Bool { stem.count >= 3 && isKnown(stem, language: .arabic) }
        var fronts = [word]
        for lead in Lexicon.egyptianLeading where word.hasPrefix(lead) { fronts.append(String(word.dropFirst(lead.count))) }
        for f in fronts {
            var bodies = [f]
            for p in Lexicon.egyptianPrefixes where f.hasPrefix(p) { bodies.append(String(f.dropFirst(p.count))) }
            for b in bodies {
                var cores = [b]
                if b.hasSuffix("ش") { cores.append(String(b.dropLast())) }
                for c in cores {
                    if c != word, known(c) { return true }
                    for e in Lexicon.egyptianEndings where c.hasSuffix(e) && known(String(c.dropLast(e.count))) { return true }
                }
            }
        }
        return false
    }

    // MARK: Franco (Arabizi) → Arabic

    private var francoIndex: [String: [(word: String, count: Int)]]?

    /// Consonant outline of an Arabic word, in the same letters Franco uses ("عامل" → "3ml").
    private static let skeletonMap: [Character: String] = [
        "ب": "b", "ت": "t", "ث": "t", "ج": "g", "ح": "7", "خ": "5", "د": "d", "ذ": "z", "ر": "r", "ز": "z",
        "س": "s", "ش": "S", "ص": "s", "ض": "d", "ط": "t", "ظ": "z", "ع": "3", "غ": "G", "ف": "f", "ق": "q",
        "ك": "k", "ل": "l", "م": "m", "ن": "n", "ه": "h",
    ]

    private static func arabicSkeleton(_ word: String) -> String {
        let map = skeletonMap
        var out = ""
        for ch in word {
            guard let m = map[ch], !out.hasSuffix(m) else { continue }   // vowels and hamza are dropped
            out += m
        }
        return out
    }

    /// Possible outlines of a Franco word ("3amel" → ["3ml"]); "2" can be ء or ق, so it gives two.
    private static func francoSkeletons(_ text: String) -> [String] {
        let s = Array(text.lowercased())
        var outlines = [""]
        var i = 0
        func append(_ options: [String]) {
            outlines = outlines.flatMap { o in options.map { opt in (opt.isEmpty || o.hasSuffix(opt)) ? o : o + opt } }
        }
        while i < s.count {
            let c = s[i]
            let next: Character? = i + 1 < s.count ? s[i + 1] : nil
            var step = 1
            switch (c, next) {
            case ("s", "h"), ("c", "h"): append(["S"]); step = 2
            case ("k", "h"), ("7", "'"): append(["5"]); step = 2
            case ("g", "h"), ("3", "'"): append(["G"]); step = 2
            case ("t", "h"): append(["t"]); step = 2
            case ("d", "h"): append(["z"]); step = 2
            default:
                switch c {
                case "2": append(["", "q"])
                case "3": append(["3"])
                case "5": append(["5"])
                case "6": append(["t"])
                case "7": append(["7"])
                case "8", "q": append(["q"])
                case "9": append(["s"])
                case "b", "p": append(["b"])
                case "t": append(["t"])
                case "g", "j": append(["g"])
                case "d": append(["d"])
                case "r": append(["r"])
                case "z": append(["z"])
                case "s", "c": append(["s"])
                case "f", "v": append(["f"])
                case "k": append(["k"])
                case "l": append(["l"])
                case "m": append(["m"])
                case "n": append(["n"])
                case "h": append(["h"])
                case "x": append(["k"]); append(["s"])
                default: break      // vowels, w, y, apostrophes
                }
            }
            i += step
        }
        return Array(Set(outlines)).filter { !$0.isEmpty }
    }

    static func looksLikeFranco(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "'") }
            && token.contains(where: \.isLetter)
    }

    static func hasFrancoDigit(_ token: String) -> Bool {
        token.contains { "2356789".contains($0) }
    }

    /// Arabic words that a Franco word most likely means ("3amel" → "عامل").
    func francoCandidates(_ token: String, limit: Int) -> [String] {
        ensureLoaded(.arabic)
        if francoIndex == nil {
            var index: [String: [(word: String, count: Int)]] = [:]
            if let list = lists[.arabic] {
                for i in 0 ..< list.count {
                    let word = list.word(i)
                    let key = Lexicon.arabicSkeleton(word)
                    guard !key.isEmpty else { continue }
                    if (index[key]?.count ?? 0) < 8 { index[key, default: []].append((word, list.count(at: i))) }
                }
            }
            francoIndex = index
        }
        var found: [String: Double] = [:]
        let typedLength = Double(token.count)
        for key in Lexicon.francoSkeletons(token) {
            for (word, count) in francoIndex?[key] ?? [] {
                // Prefer common words of a similar length.
                let lengthGap = abs(Double(word.count) - typedLength * 0.8)
                var score = log10(Double(count + 1)) - 0.15 * lengthGap
                if let uses = learned[word] { score += log2(Double(uses) + 1) }
                found[word] = max(found[word] ?? -.infinity, score)
            }
        }
        return found.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    // MARK: Next-word prediction

    /// On the phone the next-word tables are read on a background thread (about a second): the keyboard
    /// never stops for them, and next-word suggestions start once they are in. Tests read them on the spot.
    static var tablesInBackground = NSClassFromString("XCTestCase") == nil
    private var loadingTables: Set<DaadLanguage> = []

    private func ensureNextTables(_ language: DaadLanguage) {
        guard nextTables[language] == nil else { return }
        if Lexicon.tablesInBackground { preloadNextTables(language); return }
        nextTables[language] = Lexicon.loadNextTables(language)
    }

    /// Call on the main thread; the tables are stored on it too.
    private func preloadNextTables(_ language: DaadLanguage) {
        guard nextTables[language] == nil, !loadingTables.contains(language) else { return }
        loadingTables.insert(language)
        DispatchQueue.global(qos: .userInitiated).async {
            let tables = Lexicon.loadNextTables(language)
            DispatchQueue.main.async {
                self.loadingTables.remove(language)
                guard self.nextTables[language] == nil else { return }
                self.nextTables[language] = tables
                self.invalidateCache()
            }
        }
    }

    private static func loadNextTables(_ language: DaadLanguage) -> [PhraseTable] {
        let names = language == .arabic ? ["next_eg", "next_ar"] : ["next_en"]   // Egyptian first: it wins ties
        return names.map { PhraseTable(file: Bundle(for: Lexicon.self).url(forResource: $0, withExtension: "txt")) }
    }

    /// Likely next words after a context, from every table (Egyptian first), without repeats.
    private func nextWords(_ context: String, _ tables: [PhraseTable]) -> [String] {
        var merged: [String] = []
        for t in tables { for w in t.next(after: context) where !merged.contains(w) { merged.append(w) } }
        return merged
    }

    private func tableKey(_ word: String) -> String {
        String(Lexicon.stripMarks(key(word)))
    }

    private static func stripMarks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { !(0x064B...0x0652).contains($0.value) && $0.value != 0x0640 }))
    }

    /// How likely each word is to come next. `previous` nil means the start of a sentence.
    func contextScores(previous: String?, beforePrevious: String?, language: DaadLanguage) -> [String: Double] {
        ensureNextTables(language)
        let tables = nextTables[language] ?? []
        var scores: [String: Double] = [:]
        func add(_ list: [String]?, base: Double, step: Double) {
            for (i, w) in (list ?? []).enumerated() {
                scores[w, default: 0] += max(base - step * Double(i), 0.2)
            }
        }
        if let previous {
            let p1 = tableKey(previous)
            let p2 = beforePrevious.map(tableKey) ?? "<s>"
            add(nextWords(p2 + " " + p1, tables), base: 2.5, step: 0.3)     // two words of context
            add(nextWords(p1, tables), base: 1.5, step: 0.2)
            // What this user types after that word counts most.
            for (w, count) in bigrams[key(previous)] ?? [:] {
                scores[w, default: 0] += 3 + log2(Double(count) + 1)
            }
        } else {
            add(nextWords("<s>", tables), base: 1.5, step: 0.15)
        }
        if blockOffensive { scores = scores.filter { !WordExtras.isBlocked($0.key) } }
        return scores
    }

    /// Most likely next words.
    func predictions(previous: String?, beforePrevious: String?, language: DaadLanguage, limit: Int) -> [String] {
        contextScores(previous: previous, beforePrevious: beforePrevious, language: language)
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    /// The words glide typing may produce for a swipe that starts and ends near these keys, with how
    /// common each is. Only those words are built, not the whole list.
    func glideVocabulary(_ language: DaadLanguage, startKeys: Set<Character>, endKeys: Set<Character>) -> [(word: String, count: Int)] {
        ensureLoaded(language)
        guard let words = lists[language] else { return [] }
        let first = Set(startKeys.map(WordList.keyCode)), last = Set(endKeys.map(WordList.keyCode))
        var list = words.indexes(firstKeys: first, lastKeys: last).map { (word: words.word($0), count: words.count(at: $0)) }
        let top = words.top
        for (word, uses) in learned where uses >= 2 && Lexicon.language(of: word) == language && words.count(of: word) == nil {
            list.append((word: word, count: min(top, uses * 1000)))
        }
        if blockOffensive { list.removeAll { WordExtras.isBlocked($0.word) } }
        return list
    }

    func topCount(_ language: DaadLanguage) -> Int {
        ensureLoaded(language)
        return lists[language]?.top ?? 1
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
        invalidateCache()
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
        invalidateCache()
        store.removeObject(forKey: Lexicon.learnedKey)
        store.removeObject(forKey: Lexicon.bigramsKey)
        unsaved = 0
    }
}
