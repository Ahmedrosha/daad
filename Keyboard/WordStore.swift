import Foundation

/// A word list packed into a few flat arrays instead of one String object per word.
/// 100,000 Arabic words take about a third of the memory this way, and loading makes no big copies.
/// Words are kept most frequent first.
final class WordList {
    private var bytes: [UInt8] = []        // UTF-8 of every word, back to back
    private var starts: [Int32] = [0]      // word i is bytes[starts[i] ..< starts[i + 1]]
    private var norm: [UInt8] = []         // the loose (normalized) form of every word, same layout
    private var normStarts: [Int32] = [0]
    private(set) var counts: [Int32] = []
    private var slots: [Int32] = []        // open-addressing hash: word index + 1, 0 = empty
    private(set) var top = 1

    var count: Int { counts.count }

    // MARK: Reading

    func word(_ i: Int) -> String {
        String(decoding: bytes[Int(starts[i]) ..< Int(starts[i + 1])], as: UTF8.self)
    }

    func count(at i: Int) -> Int { Int(counts[i]) }

    /// How common the word is, or nil when it isn't in the list.
    func count(of word: String) -> Int? {
        index(of: Array(word.utf8)).map { Int(counts[$0]) }
    }

    /// Whether the loose form of word `i` starts with these UTF-8 bytes.
    func normalized(_ i: Int, hasPrefix p: [UInt8]) -> Bool {
        let s = Int(normStarts[i]), e = Int(normStarts[i + 1])
        guard e - s >= p.count else { return false }
        for k in 0 ..< p.count where norm[s + k] != p[k] { return false }
        return true
    }

    func normalized(_ i: Int, equals p: [UInt8]) -> Bool {
        Int(normStarts[i + 1] - normStarts[i]) == p.count && normalized(i, hasPrefix: p)
    }

    // MARK: Building

    /// Reads "word count" lines (counts may be missing in `extra` lists, see `merge`).
    init(file url: URL?, expected: Int) {
        reserve(expected)
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        WordList.forEachLine(data) { line in
            guard let space = line.firstIndex(of: 0x20),
                  let n = WordList.parseInt(line[(space + 1)...]) else { return }
            let word = Array(line[..<space])
            guard !word.isEmpty, index(of: word) == nil else { return }
            append(word, count: n)
        }
    }

    /// Adds words from a second list ("word" or "word tier"), each counted as `boost(tier)` or kept
    /// at its own count when that's higher. Call `sortByCount()` afterwards.
    func merge(file url: URL?, boost: (Int) -> Int) {
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        WordList.forEachLine(data) { line in
            let space = line.firstIndex(of: 0x20)
            let word = Array(space.map { line[..<$0] } ?? line[...])
            guard !word.isEmpty else { return }
            let tier = space.flatMap { WordList.parseInt(line[($0 + 1)...]) } ?? 1
            let n = boost(max(tier, 1))
            if let i = index(of: word) {
                counts[i] = max(counts[i], Int32(clamping: n))
            } else {
                append(word, count: n)
            }
        }
    }

    /// Puts the most frequent words first (completions stop after the first matches).
    func sortByCount() {
        let order = (0 ..< count).sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
        var b: [UInt8] = [], s: [Int32] = [0], nb: [UInt8] = [], ns: [Int32] = [0], c: [Int32] = []
        b.reserveCapacity(bytes.count); nb.reserveCapacity(norm.count)
        s.reserveCapacity(count + 1); ns.reserveCapacity(count + 1); c.reserveCapacity(count)
        for i in order {
            b.append(contentsOf: bytes[Int(starts[i]) ..< Int(starts[i + 1])]); s.append(Int32(b.count))
            nb.append(contentsOf: norm[Int(normStarts[i]) ..< Int(normStarts[i + 1])]); ns.append(Int32(nb.count))
            c.append(counts[i])
        }
        bytes = b; starts = s; norm = nb; normStarts = ns; counts = c
        slots = [Int32](repeating: 0, count: slots.count)
        for i in 0 ..< count { insertSlot(i) }
    }

    private func reserve(_ expected: Int) {
        var size = 1024
        while size < expected * 2 { size <<= 1 }
        slots = [Int32](repeating: 0, count: size)
        counts.reserveCapacity(expected)
        starts.reserveCapacity(expected + 1)
        normStarts.reserveCapacity(expected + 1)
    }

    private func append(_ word: [UInt8], count n: Int) {
        if (count + 1) * 2 > slots.count { grow() }
        bytes.append(contentsOf: word)
        starts.append(Int32(bytes.count))
        let loose = Lexicon.normalize(String(decoding: word, as: UTF8.self))
        norm.append(contentsOf: loose.utf8)
        normStarts.append(Int32(norm.count))
        counts.append(Int32(clamping: n))
        top = max(top, n)
        insertSlot(count - 1)
    }

    private func grow() {
        slots = [Int32](repeating: 0, count: slots.count * 2)
        for i in 0 ..< count { insertSlot(i) }
    }

    // MARK: Hashing

    private static func hash<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
        var h: UInt64 = 0xcbf29ce484222325           // FNV-1a
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    private func insertSlot(_ i: Int) {
        let mask = slots.count - 1
        var j = WordList.hash(bytes[Int(starts[i]) ..< Int(starts[i + 1])]) & mask
        while slots[j] != 0 { j = (j + 1) & mask }
        slots[j] = Int32(i + 1)
    }

    private func index(of word: [UInt8]) -> Int? {
        guard !slots.isEmpty else { return nil }
        let mask = slots.count - 1
        var j = WordList.hash(word) & mask
        while slots[j] != 0 {
            let i = Int(slots[j]) - 1
            let s = Int(starts[i]), e = Int(starts[i + 1])
            if e - s == word.count && bytes[s ..< e].elementsEqual(word) { return i }
            j = (j + 1) & mask
        }
        return nil
    }

    // MARK: Parsing without copying the file

    static func forEachLine(_ data: Data, _ body: (ArraySlice<UInt8>) -> Void) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let all = raw.bindMemory(to: UInt8.self)
            var lineStart = 0
            for i in 0 ... all.count {
                guard i == all.count || all[i] == 0x0A else { continue }
                var end = i
                if end > lineStart, all[end - 1] == 0x0D { end -= 1 }
                if end > lineStart { body(ArraySlice(UnsafeBufferPointer(rebasing: all[lineStart ..< end]))) }
                lineStart = i + 1
            }
        }
    }

    static func parseInt(_ s: ArraySlice<UInt8>) -> Int? {
        var n = 0, any = false
        for b in s {
            guard b >= 0x30, b <= 0x39 else { break }
            n = n &* 10 &+ Int(b - 0x30); any = true
        }
        return any ? n : nil
    }
}

/// Next-word tables ("context<TAB>w1 w2 w3"), packed the same way: one string per context, split only
/// when that context is looked up.
final class PhraseTable {
    private var keys: [UInt8] = []
    private var keyStarts: [Int32] = [0]
    private var values: [UInt8] = []
    private var valueStarts: [Int32] = [0]
    private var slots: [Int32] = []

    init(file url: URL?) {
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        var lines = 0
        data.withUnsafeBytes { raw in lines = raw.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) } }
        var size = 1024
        while size < (lines + 1) * 2 { size <<= 1 }
        slots = [Int32](repeating: 0, count: size)
        WordList.forEachLine(data) { line in
            guard let tab = line.firstIndex(of: 0x09) else { return }
            let key = line[..<tab], value = line[(tab + 1)...]
            guard !key.isEmpty, !value.isEmpty, find(Array(key)) == nil else { return }
            keys.append(contentsOf: key); keyStarts.append(Int32(keys.count))
            values.append(contentsOf: value); valueStarts.append(Int32(values.count))
            insertSlot(keyStarts.count - 2)
        }
    }

    /// The likely next words after this context, best first.
    func next(after context: String) -> [String] {
        guard let i = find(Array(context.utf8)) else { return [] }
        let slice = values[Int(valueStarts[i]) ..< Int(valueStarts[i + 1])]
        return slice.split(separator: 0x20).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func hash<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    private func insertSlot(_ i: Int) {
        let mask = slots.count - 1
        var j = PhraseTable.hash(keys[Int(keyStarts[i]) ..< Int(keyStarts[i + 1])]) & mask
        while slots[j] != 0 { j = (j + 1) & mask }
        slots[j] = Int32(i + 1)
    }

    private func find(_ key: [UInt8]) -> Int? {
        guard !slots.isEmpty else { return nil }
        let mask = slots.count - 1
        var j = PhraseTable.hash(key) & mask
        while slots[j] != 0 {
            let i = Int(slots[j]) - 1
            let s = Int(keyStarts[i]), e = Int(keyStarts[i + 1])
            if e - s == key.count && keys[s ..< e].elementsEqual(key) { return i }
            j = (j + 1) & mask
        }
        return nil
    }
}
