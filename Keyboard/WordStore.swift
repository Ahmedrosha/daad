import Foundation

/// Builds a word list from the bundled text files into a few flat arrays, then writes it out in the
/// layout `WordList` reads. Used at build time (scripts/dictgen, so the keyboard opens a ready file)
/// and, if that file is missing, by the keyboard itself. Words are kept most frequent first.
final class WordListBuilder {
    private var bytes: [UInt8] = []        // UTF-8 of every word, back to back
    private var starts: [Int32] = [0]      // word i is bytes[starts[i] ..< starts[i + 1]]
    private var norm: [UInt8] = []         // the loose (normalized) form of every word, same layout
    private var normStarts: [Int32] = [0]
    private(set) var counts: [Int32] = []
    private var slots: [Int32] = []        // open-addressing hash: word index + 1, 0 = empty
    private var byNorm: [Int32] = []       // word indexes ordered by loose form, for prefix look-ups
    private var firstKey: [UInt16] = []    // first and last keyboard letter of each word (glide typing)
    private var lastKey: [UInt16] = []
    private(set) var top = 1

    var count: Int { counts.count }

    // MARK: Reading

    func word(_ i: Int) -> String {
        String(decoding: bytes[Int(starts[i]) ..< Int(starts[i + 1])], as: UTF8.self)
    }

    func count(at i: Int) -> Int { Int(counts[i]) }

    /// How common the word is, or nil when it isn't in the list.
    func count(of word: String) -> Int? {
        var w = word
        return w.withUTF8 { index(of: $0) }.map { Int(counts[$0]) }
    }

    // MARK: Look-ups by prefix (no scan of the whole list)

    private func compareNorm(_ i: Int, with p: [UInt8], prefixOnly: Bool) -> Int {
        let s = Int(normStarts[i]), n = Int(normStarts[i + 1]) - s
        let m = min(n, p.count)
        for k in 0 ..< m where norm[s + k] != p[k] { return norm[s + k] < p[k] ? -1 : 1 }
        if n < p.count { return -1 }
        return prefixOnly || n == p.count ? 0 : 1
    }

    /// Positions in `byNorm` of every word whose loose form starts with these bytes.
    private func prefixRange(_ p: [UInt8]) -> Range<Int> {
        var lo = 0, hi = byNorm.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compareNorm(Int(byNorm[mid]), with: p, prefixOnly: true) < 0 { lo = mid + 1 } else { hi = mid }
        }
        let start = lo
        hi = byNorm.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compareNorm(Int(byNorm[mid]), with: p, prefixOnly: true) <= 0 { lo = mid + 1 } else { hi = mid }
        }
        return start ..< lo
    }

    /// The most frequent words whose loose form starts with `prefix` (word indexes, most frequent first).
    func indexes(withPrefix prefix: String, limit: Int) -> [Int] {
        let p = Array(prefix.utf8)
        guard !p.isEmpty else { return [] }
        let range = prefixRange(p)
        guard !range.isEmpty else { return [] }
        // A smaller index means a more frequent word. Keep the `limit` smallest.
        if range.count <= limit { return byNorm[range].map { Int($0) }.sorted() }
        var best: [Int32] = []
        best.reserveCapacity(limit + 1)
        var worst = Int32.max
        for pos in range {
            let i = byNorm[pos]
            if best.count < limit {
                best.append(i)
                if best.count == limit { best.sort(); worst = best[limit - 1] }
            } else if i < worst {
                let at = best.firstIndex { $0 > i } ?? limit - 1
                best.insert(i, at: at)
                best.removeLast()
                worst = best[limit - 1]
            }
        }
        if best.count < limit { best.sort() }
        return best.map { Int($0) }
    }

    /// Words whose loose form is exactly `form` (word indexes).
    func indexes(withNormalized form: String) -> [Int] {
        let p = Array(form.utf8)
        guard !p.isEmpty else { return [] }
        return byNorm[prefixRange(p)].map { Int($0) }.filter { Int(normStarts[$0 + 1] - normStarts[$0]) == p.count }
    }

    /// Words that start and end on these keys (word indexes), for glide typing.
    func indexes(firstKeys: Set<UInt16>, lastKeys: Set<UInt16>) -> [Int] {
        var out: [Int] = []
        for i in 0 ..< count where firstKeys.contains(firstKey[i]) && lastKeys.contains(lastKey[i]) { out.append(i) }
        return out
    }

    /// Call once after loading (and after `sortByCount`).
    func buildIndexes() {
        byNorm = (0 ..< Int32(count)).sorted { a, b in
            let sa = Int(normStarts[Int(a)]), ea = Int(normStarts[Int(a) + 1])
            let sb = Int(normStarts[Int(b)]), eb = Int(normStarts[Int(b) + 1])
            return norm[sa ..< ea].lexicographicallyPrecedes(norm[sb ..< eb])
        }
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
        WordListBuilder.forEachLine(data) { line in
            guard let space = line.firstIndex(of: 0x20),
                  let n = WordListBuilder.parseInt(line[(space + 1)...]) else { return }
            let word = Array(line[..<space])
            guard !word.isEmpty, index(of: word) == nil else { return }
            append(word, count: n)
        }
    }

    /// Adds words from a second list ("word" or "word tier"), each counted as `boost(tier)` or kept
    /// at its own count when that's higher. Call `sortByCount()` afterwards.
    func merge(file url: URL?, boost: (Int) -> Int) {
        guard let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        WordListBuilder.forEachLine(data) { line in
            let space = line.firstIndex(of: 0x20)
            let word = Array(space.map { line[..<$0] } ?? line[...])
            guard !word.isEmpty else { return }
            let tier = space.flatMap { WordListBuilder.parseInt(line[($0 + 1)...]) } ?? 1
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
        var fk: [UInt16] = [], lk: [UInt16] = []
        fk.reserveCapacity(count); lk.reserveCapacity(count)
        b.reserveCapacity(bytes.count); nb.reserveCapacity(norm.count)
        s.reserveCapacity(count + 1); ns.reserveCapacity(count + 1); c.reserveCapacity(count)
        for i in order {
            b.append(contentsOf: bytes[Int(starts[i]) ..< Int(starts[i + 1])]); s.append(Int32(b.count))
            nb.append(contentsOf: norm[Int(normStarts[i]) ..< Int(normStarts[i + 1])]); ns.append(Int32(nb.count))
            c.append(counts[i])
            fk.append(firstKey[i]); lk.append(lastKey[i])
        }
        bytes = b; starts = s; norm = nb; normStarts = ns; counts = c; firstKey = fk; lastKey = lk
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
        let text = String(decoding: word, as: UTF8.self)
        let loose = TextFold.normalize(text)
        let letters = TextFold.keyLetters(of: text)
        firstKey.append(letters.first.map(WordListBuilder.keyCode) ?? 0)
        lastKey.append(letters.last.map(WordListBuilder.keyCode) ?? 0)
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

    /// A keyboard letter as a small number (0 = not a single simple letter).
    static func keyCode(_ ch: Character) -> UInt16 {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let v = scalars.first?.value, v <= 0xFFFF else { return 0 }
        return UInt16(v)
    }

    // MARK: Hashing

    static func hash<C: Collection>(_ bytes: C) -> Int where C.Element == UInt8 {
        var h: UInt64 = 0xcbf29ce484222325           // FNV-1a
        for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: h)
    }

    private func insertSlot(_ i: Int) {
        let mask = slots.count - 1
        var j = WordListBuilder.hash(bytes[Int(starts[i]) ..< Int(starts[i + 1])]) & mask
        while slots[j] != 0 { j = (j + 1) & mask }
        slots[j] = Int32(i + 1)
    }

    private func index<C: Collection>(of word: C) -> Int? where C.Element == UInt8 {
        guard !slots.isEmpty else { return nil }
        let mask = slots.count - 1
        var j = WordListBuilder.hash(word) & mask
        while slots[j] != 0 {
            let i = Int(slots[j]) - 1
            let s = Int(starts[i]), e = Int(starts[i + 1])
            if e - s == word.count && bytes[s ..< e].elementsEqual(word) { return i }
            j = (j + 1) & mask
        }
        return nil
    }

    // MARK: The bundled lists

    /// The Arabic list (with the Egyptian words merged in) or the English one, as the keyboard uses it.
    static func make(main: URL?, egyptian: URL?, arabic: Bool) -> WordListBuilder {
        let list = WordListBuilder(file: main, expected: arabic ? 105_000 : 50_000)
        // Everyday Egyptian words that subtitles rarely contain, ranked as fairly common.
        // "word" = everyday word, ranked high; "word 3" = a generated verb form, ranked a bit lower.
        if arabic {
            let top = list.top
            list.merge(file: egyptian) { tier in max(top / (40 * tier), 1) }
            list.sortByCount()
        }
        list.buildIndexes()
        return list
    }

    /// The list in `WordList`'s file layout (see there).
    func serialize() -> Data {
        var d = Data()
        func put<T>(_ a: [T]) { a.withUnsafeBytes { d.append(contentsOf: $0) } }
        put([WordList.magic, WordList.version, UInt32(count), UInt32(clamping: top), UInt32(slots.count),
             UInt32(bytes.count), UInt32(norm.count), 0])
        put(starts); put(normStarts); put(counts); put(slots); put(byNorm); put(firstKey); put(lastKey)
        while d.count % 4 != 0 { d.append(0) }
        d.append(contentsOf: bytes)
        d.append(contentsOf: norm)
        return d
    }

    /// Ready to read (a copy in memory; the keyboard normally maps the prebuilt file instead).
    func finish() -> WordList { WordList(data: serialize())! }

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

/// A word list ready to read, laid out as one block of memory, most frequent word first. The keyboard
/// maps the file built at build time (dict_ar.bin / dict_en.bin): nothing is parsed or copied on
/// opening, and iOS can drop and re-read the mapped pages instead of counting them against the
/// keyboard's memory.
///
/// Layout (little-endian): 8 UInt32 header (magic, version, count, top, slot count, bytes length,
/// loose-forms length, 0), then Int32 starts[count+1], normStarts[count+1], counts[count],
/// slots[slot count], byNorm[count], UInt16 firstKey[count], lastKey[count], padding to 4,
/// the UTF-8 words back to back, the loose forms back to back.
final class WordList {
    static let magic: UInt32 = 0x4441_4144      // "DAAD"
    static let version: UInt32 = 1

    let count: Int
    let top: Int
    private let starts, normStarts, counts, slots, byNorm: UnsafeBufferPointer<Int32>
    private let firstKey, lastKey: UnsafeBufferPointer<UInt16>
    private let bytes, norm: UnsafeBufferPointer<UInt8>
    private let release: () -> Void

    /// Maps a prebuilt file; nil if it's missing or not in this layout.
    convenience init?(mapping url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_size > 32 else { return nil }
        let size = Int(st.st_size)
        guard let p = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), p != MAP_FAILED else { return nil }
        self.init(base: UnsafeRawPointer(p), length: size) { munmap(p, size) }
    }

    /// Reads a list from bytes in this layout (kept in a private copy).
    convenience init?(data: Data) {
        let size = data.count
        let p = UnsafeMutableRawPointer.allocate(byteCount: max(size, 1), alignment: 8)
        data.withUnsafeBytes { if let b = $0.baseAddress { p.copyMemory(from: b, byteCount: size) } }
        self.init(base: UnsafeRawPointer(p), length: size) { p.deallocate() }
    }

    private init?(base: UnsafeRawPointer, length: Int, release: @escaping () -> Void) {
        func fail() -> Bool { release(); return false }
        guard length >= 32 else { _ = fail(); return nil }
        let h = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt32.self), count: 8)
        guard h[0] == WordList.magic, h[1] == WordList.version else { _ = fail(); return nil }
        let n = Int(h[2]), slotCount = Int(h[4]), bytesLen = Int(h[5]), normLen = Int(h[6])
        var offset = 32
        func ints(_ k: Int) -> UnsafeBufferPointer<Int32> {
            defer { offset += k * 4 }
            return UnsafeBufferPointer(start: (base + offset).assumingMemoryBound(to: Int32.self), count: k)
        }
        func shorts(_ k: Int) -> UnsafeBufferPointer<UInt16> {
            defer { offset += k * 2 }
            return UnsafeBufferPointer(start: (base + offset).assumingMemoryBound(to: UInt16.self), count: k)
        }
        func raw(_ k: Int) -> UnsafeBufferPointer<UInt8> {
            defer { offset += k }
            return UnsafeBufferPointer(start: (base + offset).assumingMemoryBound(to: UInt8.self), count: k)
        }
        let expected = 32 + (n + 1) * 8 + n * 4 + slotCount * 4 + n * 4 + n * 4
        let padded = (expected + 3) / 4 * 4
        guard padded + bytesLen + normLen <= length, slotCount > 0, slotCount & (slotCount - 1) == 0 else {
            _ = fail(); return nil
        }
        count = n
        top = Int(h[3])
        starts = ints(n + 1); normStarts = ints(n + 1); counts = ints(n); slots = ints(slotCount); byNorm = ints(n)
        firstKey = shorts(n); lastKey = shorts(n)
        offset = padded
        bytes = raw(bytesLen); norm = raw(normLen)
        self.release = release
    }

    deinit { release() }

    // MARK: Reading

    func word(_ i: Int) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[Int(starts[i]) ..< Int(starts[i + 1])]), as: UTF8.self)
    }

    func count(at i: Int) -> Int { Int(counts[i]) }

    /// How common the word is, or nil when it isn't in the list.
    func count(of word: String) -> Int? {
        var w = word
        return w.withUTF8 { index(of: $0) }.map { Int(counts[$0]) }
    }

    /// A keyboard letter as a small number (0 = not a single simple letter).
    static func keyCode(_ ch: Character) -> UInt16 { WordListBuilder.keyCode(ch) }

    private func compareNorm(_ i: Int, with p: [UInt8], prefixOnly: Bool) -> Int {
        let s = Int(normStarts[i]), n = Int(normStarts[i + 1]) - s
        let m = min(n, p.count)
        for k in 0 ..< m where norm[s + k] != p[k] { return norm[s + k] < p[k] ? -1 : 1 }
        if n < p.count { return -1 }
        return prefixOnly || n == p.count ? 0 : 1
    }

    private func prefixRange(_ p: [UInt8]) -> Range<Int> {
        var lo = 0, hi = byNorm.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compareNorm(Int(byNorm[mid]), with: p, prefixOnly: true) < 0 { lo = mid + 1 } else { hi = mid }
        }
        let start = lo
        hi = byNorm.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compareNorm(Int(byNorm[mid]), with: p, prefixOnly: true) <= 0 { lo = mid + 1 } else { hi = mid }
        }
        return start ..< lo
    }

    /// The most frequent words whose loose form starts with `prefix` (word indexes, most frequent first).
    func indexes(withPrefix prefix: String, limit: Int) -> [Int] {
        let p = Array(prefix.utf8)
        guard !p.isEmpty else { return [] }
        let range = prefixRange(p)
        guard !range.isEmpty else { return [] }
        if range.count <= limit { return byNorm[range].map { Int($0) }.sorted() }
        var best: [Int32] = []
        best.reserveCapacity(limit + 1)
        var worst = Int32.max
        for pos in range {
            let i = byNorm[pos]
            if best.count < limit {
                best.append(i)
                if best.count == limit { best.sort(); worst = best[limit - 1] }
            } else if i < worst {
                let at = best.firstIndex { $0 > i } ?? limit - 1
                best.insert(i, at: at)
                best.removeLast()
                worst = best[limit - 1]
            }
        }
        if best.count < limit { best.sort() }
        return best.map { Int($0) }
    }

    /// Words whose loose form is exactly `form` (word indexes).
    func indexes(withNormalized form: String) -> [Int] {
        let p = Array(form.utf8)
        guard !p.isEmpty else { return [] }
        return byNorm[prefixRange(p)].map { Int($0) }.filter { Int(normStarts[$0 + 1] - normStarts[$0]) == p.count }
    }

    /// Words that start and end on these keys (word indexes), for glide typing.
    func indexes(firstKeys: Set<UInt16>, lastKeys: Set<UInt16>) -> [Int] {
        var out: [Int] = []
        for i in 0 ..< count where firstKeys.contains(firstKey[i]) && lastKeys.contains(lastKey[i]) { out.append(i) }
        return out
    }

    private func index<C: Collection>(of word: C) -> Int? where C.Element == UInt8 {
        let mask = slots.count - 1
        var j = WordListBuilder.hash(word) & mask
        while slots[j] != 0 {
            let i = Int(slots[j]) - 1
            let s = Int(starts[i]), e = Int(starts[i + 1])
            if e - s == word.count && bytes[s ..< e].elementsEqual(word) { return i }
            j = (j + 1) & mask
        }
        return nil
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
        WordListBuilder.forEachLine(data) { line in
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
