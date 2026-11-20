import UIKit

/// Turns a finger path across the keys into the most likely words.
/// Compares the path's shape with the ideal path of each word that starts and ends near
/// the same keys, then prefers common words.
enum GlideDecoder {
    private static let samples = 32

    static func decode(path: [CGPoint],
                       keyCenters: [Character: CGPoint],
                       keyWidth: CGFloat,
                       language: DaadLanguage,
                       lexicon: Lexicon) -> [String] {
        guard path.count >= 2, !keyCenters.isEmpty, keyWidth > 0 else { return [] }
        let startKeys = nearestKeys(to: path[0], in: keyCenters, count: 3, keyWidth: keyWidth)
        let endKeys = nearestKeys(to: path[path.count - 1], in: keyCenters, count: 3, keyWidth: keyWidth)
        let userPath = resample(path, count: samples)
        let maxLog = log(Double(max(lexicon.topCount(language), 2)))

        var best: [(word: String, score: Double)] = []
        for (word, count) in lexicon.glideVocabulary(language) {
            let letters = keyLetters(of: word, language: language)
            guard letters.count >= 2,
                  let first = letters.first, startKeys.contains(first),
                  let last = letters.last, endKeys.contains(last) else { continue }

            var points: [CGPoint] = []
            var valid = true
            for ch in letters {
                guard let p = keyCenters[ch] else { valid = false; break }
                if points.last != p { points.append(p) }
            }
            guard valid else { continue }
            if points.count == 1 { points.append(points[0]) }

            let shape = averageDistance(userPath, resample(points, count: samples)) / Double(keyWidth)
            let rarity = 1 - log(Double(max(count, 1))) / maxLog     // 0 = very common, 1 = rare
            let score = shape + 0.7 * rarity
            best.append((word, score))
        }
        best.sort { $0.score < $1.score }
        return Array(best.prefix(4).map { $0.word })
    }

    /// Maps a word's letters to the keys that produce them (أ → ا, harakat dropped, …).
    static func keyLetters(of word: String, language: DaadLanguage) -> [Character] {
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

    private static func nearestKeys(to point: CGPoint, in centers: [Character: CGPoint], count: Int, keyWidth: CGFloat) -> Set<Character> {
        let sorted = centers.sorted { distance($0.value, point) < distance($1.value, point) }
        var result = Set<Character>()
        for (i, item) in sorted.enumerated() {
            if i >= count { break }
            if i > 0 && distance(item.value, point) > keyWidth * 1.3 { break }
            result.insert(item.key)
        }
        return result
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func averageDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return .greatestFiniteMagnitude }
        var total: CGFloat = 0
        for i in 0..<n { total += distance(a[i], b[i]) }
        return Double(total / CGFloat(n))
    }

    /// Spreads `count` points evenly along a polyline.
    static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1 else { return Array(repeating: points.first ?? .zero, count: count) }
        var length: CGFloat = 0
        for i in 1..<points.count { length += distance(points[i - 1], points[i]) }
        guard length > 0 else { return Array(repeating: points[0], count: count) }

        let step = length / CGFloat(count - 1)
        var result: [CGPoint] = [points[0]]
        var carried: CGFloat = 0
        var prev = points[0]
        var i = 1
        while i < points.count && result.count < count {
            let next = points[i]
            let segment = distance(prev, next)
            if carried + segment >= step && segment > 0 {
                let t = (step - carried) / segment
                let p = CGPoint(x: prev.x + t * (next.x - prev.x), y: prev.y + t * (next.y - prev.y))
                result.append(p)
                prev = p
                carried = 0
            } else {
                carried += segment
                prev = next
                i += 1
            }
        }
        while result.count < count { result.append(points[points.count - 1]) }
        return result
    }
}
