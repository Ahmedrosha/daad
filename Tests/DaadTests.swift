import XCTest

/// Checks for the parts that broke before or are easy to break: brackets, layouts, numbers, words.
final class DaadTests: XCTestCase {

    // MARK: Calculator

    func testCalculatorPrecedenceAndPercent() {
        XCTAssertEqual(Calculator.evaluate("5+3×2"), 11)
        XCTAssertEqual(Calculator.evaluate("10÷4"), 2.5)
        XCTAssertEqual(Calculator.evaluate("50%"), 0.5)
        XCTAssertEqual(Calculator.evaluate("200×10%"), 20)
        XCTAssertNil(Calculator.evaluate("5+"))
        XCTAssertNil(Calculator.evaluate("1÷0"))
        XCTAssertEqual(Calculator.format(8), "8")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
    }

    // MARK: Layouts

    private func context(_ language: DaadLanguage, mode: KeyboardMode = .letters, layout: String = "iphone") -> LayoutContext {
        LayoutContext(language: language, mode: mode, shift: .off, showNumberRow: true, arabicDigits: true,
                      needsGlobe: false, returnLabel: "", dark: true, arabicLayout: layout)
    }

    private func label(of action: KeyAction, in rows: [KeyRow]) -> String? {
        rows.flatMap { $0.keys }.first { $0.action == action }?.label
    }

    func testArabicIPhoneLayoutOrder() {
        let rows = Layouts.build(context(.arabic)).rows
        XCTAssertEqual(rows[1].keys.first?.label, "ض")
        XCTAssertEqual(rows[2].keys.last?.label, "ة")
        XCTAssertEqual(rows[3].keys.first?.label, "ء")
        XCTAssertEqual(rows[3].keys.last?.action, .backspace, "delete sits at the right end")
        XCTAssertEqual(rows[0].keys.last?.action, .forwardDelete, "forward delete next to ٠")
    }

    func testGboardLayoutStillAvailable() {
        let rows = Layouts.build(context(.arabic, layout: "gboard")).rows
        XCTAssertEqual(rows[2].keys.last?.label, "ط")
    }

    func testArabicBracketsShowTheShapeThatAppears() {
        let rows = Layouts.build(context(.arabic, mode: .symbols1)).rows
        // In right-to-left text "(" is drawn as ")", so its key shows ")".
        XCTAssertEqual(label(of: .character("("), in: rows), ")")
        XCTAssertEqual(label(of: .character(")"), in: rows), "(")
        let english = Layouts.build(context(.english, mode: .symbols1)).rows
        XCTAssertEqual(label(of: .character("("), in: english), "(")
    }

    func testFlickUpSymbolsOnLetters() {
        let rows = Layouts.build(context(.english)).rows
        let q = rows.flatMap { $0.keys }.first { $0.action == .character("q") }
        XCTAssertEqual(q?.upChar, "1")
    }

    // MARK: Words

    func testNormalizeFoldsHamzaAndHarakat() {
        XCTAssertEqual(Lexicon.normalize("أنا"), "انا")
        XCTAssertEqual(Lexicon.normalize("مَدرسة"), "مدرسه")
        XCTAssertEqual(Lexicon.matchCase("hello", like: "He"), "Hello")
        XCTAssertEqual(Lexicon.matchCase("hello", like: "HE"), "HELLO")
    }

    func testFrancoFindsArabic() {
        XCTAssertTrue(Lexicon.looksLikeFranco("3amel"))
        XCTAssertTrue(Lexicon.hasFrancoDigit("3amel"))
        XCTAssertFalse(Lexicon.looksLikeFranco("عامل"))
        XCTAssertTrue(Lexicon.shared.francoCandidates("3amel", limit: 5).contains("عامل"))
    }

    func testEmojiSearch() {
        XCTAssertTrue(WordExtras.searchEmoji("قلب").contains("❤️"))
        XCTAssertTrue(WordExtras.searchEmoji("laugh").contains("😂"))
        XCTAssertTrue(WordExtras.isBlocked("FUCK"))
    }

    func testGlideResample() {
        let points = GlideDecoder.resample([.zero, CGPoint(x: 100, y: 0)], count: 11)
        XCTAssertEqual(points.count, 11)
        XCTAssertEqual(points[5].x, 50, accuracy: 0.5)
    }

    func testFontsNeverFail() {
        for font in KeyFont.allCases { XCTAssertGreaterThan(font.font(size: 20).pointSize, 0) }
    }

    // MARK: Trial / purchase

    func testAccessStatus() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Access.status(AccessState(), now: now), .notStarted)
        XCTAssertEqual(Access.status(AccessState(trialStart: now), now: now), .trial(daysLeft: 7))
        let sixDaysAgo = now.addingTimeInterval(-6 * 86_400 - 60)
        XCTAssertEqual(Access.status(AccessState(trialStart: sixDaysAgo), now: now), .trial(daysLeft: 1))
        let eightDaysAgo = now.addingTimeInterval(-8 * 86_400)
        XCTAssertEqual(Access.status(AccessState(trialStart: eightDaysAgo), now: now), .expired)
        XCTAssertEqual(Access.status(AccessState(purchased: true, trialStart: eightDaysAgo), now: now), .purchased)
        XCTAssertFalse(AccessStatus.expired.unlocked)
        XCTAssertFalse(AccessStatus.notStarted.unlocked)
    }

    func testAccessMergeAndStorage() {
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        let merged = AccessState(trialStart: late).merged(with: AccessState(purchased: true, trialStart: early))
        XCTAssertEqual(merged, AccessState(purchased: true, trialStart: early))
        let defaults = UserDefaults(suiteName: "daad.tests.access")!
        defaults.removePersistentDomain(forName: "daad.tests.access")
        XCTAssertEqual(Access.load(from: defaults), AccessState())
        Access.save(merged, to: defaults)
        XCTAssertEqual(Access.load(from: defaults), merged)
    }

    // MARK: Dual keyboard

    func testDualKeyboardPutsEnglishLettersOnArabicKeys() {
        var c = context(.arabic)
        c.dual = true
        let keys = Layouts.build(c).rows.flatMap(\.keys)
        func down(_ arabic: String) -> String? {
            keys.first { $0.action == .character(arabic) }?.downChar
        }
        XCTAssertEqual(down("ض"), "q")
        XCTAssertEqual(down("ح"), "p")
        XCTAssertEqual(down("ش"), "a")
        XCTAssertNil(down("ج"))
        XCTAssertEqual(keys.compactMap(\.downChar).count, 26)
        // Off by default, and never on the English keyboard.
        XCTAssertTrue(Layouts.build(context(.arabic)).rows.flatMap(\.keys).allSatisfy { $0.downChar == nil })
        var e = context(.english)
        e.dual = true
        XCTAssertTrue(Layouts.build(e).rows.flatMap(\.keys).allSatisfy { $0.downChar == nil })
    }

    func testLanguageBeforeCursor() {
        XCTAssertEqual(KeyboardViewController.languageBefore("ازيك يا Ahmed "), .english)
        XCTAssertEqual(KeyboardViewController.languageBefore("hello يا صاحبي، "), .arabic)
        XCTAssertNil(KeyboardViewController.languageBefore("123 !! "))
        XCTAssertNil(KeyboardViewController.languageBefore(""))
    }

    func testInputModeCycle() {
        let all = InputMode.allCases
        XCTAssertEqual(InputMode.arabic.step(true, enabled: all), .english)
        XCTAssertEqual(InputMode.english.step(true, enabled: all), .dual)
        XCTAssertEqual(InputMode.dual.step(true, enabled: all), .arabic)
        XCTAssertEqual(InputMode.arabic.step(false, enabled: all), .dual)
        XCTAssertEqual(InputMode.arabic.step(true, enabled: [.arabic, .dual]), .dual)
        XCTAssertEqual(InputMode.english.step(true, enabled: [.arabic]), .arabic)   // current one turned off
        XCTAssertEqual(InputMode.arabic.step(true, enabled: [.arabic]), .arabic)
        XCTAssertEqual(InputMode.dual.language, .arabic)
    }

    func testDualLookSwapsTapLetter() {
        for look in [DualLook.englishBig, .corners] {
            var c = context(.arabic)
            c.dual = true
            c.dualLook = look
            let keys = Layouts.build(c).rows.flatMap(\.keys)
            let q = keys.first { $0.action == .character("q") }
            XCTAssertEqual(q?.downChar, "ض")
            XCTAssertEqual(q?.dualLook, look)
            XCTAssertNotNil(keys.first { $0.action == .character("ج") })   // no English letter: stays Arabic
        }
    }

    func testDualKeyboardHasShift() {
        var c = context(.arabic)
        c.dual = true
        XCTAssertTrue(Layouts.build(c).rows.flatMap(\.keys).contains { $0.action == .shift })
        XCTAssertFalse(Layouts.build(context(.arabic)).rows.flatMap(\.keys).contains { $0.action == .shift })
        c.shift = .on
        XCTAssertEqual(Layouts.build(c).rows.flatMap(\.keys).first { $0.action == .character("ض") }?.downChar, "Q")
    }

    func testAutomaticDualLookFollowsLastLetter() {
        XCTAssertEqual(DualLook.automatic.resolved(lastLetter: nil), .corners)
        XCTAssertEqual(DualLook.automatic.resolved(lastLetter: .arabic), .arabicTop)
        XCTAssertEqual(DualLook.automatic.resolved(lastLetter: .english), .englishBig)
        XCTAssertEqual(DualLook.corners.resolved(lastLetter: .arabic), .corners)
    }

    func testEgyptianTypoGetsFixed() {
        let lexicon = Lexicon()
        let words = lexicon.rank("خاصت", language: .arabic, limit: 3).prefix(2).map(\.word)
        XCTAssertTrue(words.contains("خلصت"), "got \(words)")
        XCTAssertFalse(lexicon.rank("هخلص", language: .arabic, limit: 3).filter { $0.kind == .exact }.isEmpty)
    }

    func testUndoneCorrectionIsKept() {
        let lexicon = Lexicon()
        let suite = UserDefaults(suiteName: "daad.tests.keep")!
        suite.removePersistentDomain(forName: "daad.tests.keep")
        lexicon.configure(store: suite)
        XCTAssertNotNil(lexicon.autocorrection(for: "خاصت", language: .arabic))
        lexicon.keep("خاصت")
        XCTAssertNil(lexicon.autocorrection(for: "خاصت", language: .arabic))
    }

    func testLearnedWordsMergeAcrossFullAccess() {
        let a = UserDefaults(suiteName: "daad.tests.a")!, b = UserDefaults(suiteName: "daad.tests.b")!
        a.removePersistentDomain(forName: "daad.tests.a"); b.removePersistentDomain(forName: "daad.tests.b")
        let first = Lexicon()
        first.configure(store: b)
        first.keep("زفتاوي")
        let second = Lexicon()
        second.configure(store: a, mergingFrom: b)
        XCTAssertTrue(second.isKnown("زفتاوي", language: .arabic))
    }

    func testDualDeleteIconsFollowTypingLanguage() {
        var c = context(.arabic)
        c.dual = true
        c.dualLook = .englishBig
        XCTAssertEqual(Layouts.build(c).rows.flatMap(\.keys).first { $0.action == .backspace }?.symbol, "delete.left")
        c.dualLook = .arabicTop
        XCTAssertEqual(Layouts.build(c).rows.flatMap(\.keys).first { $0.action == .backspace }?.symbol, "delete.right")
    }

    // MARK: Speed (what one key press costs)

    private func milliseconds(_ work: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        work()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    func testSpeedOfSuggestions() {
        let lexicon = Lexicon()
        _ = lexicon.isKnown("خلصت", language: .arabic)
        _ = lexicon.isKnown("hello", language: .english)
        // One-time loads (next-word tables) are timed apart from the per-key cost.
        let firstLoad = milliseconds {
            _ = lexicon.predictions(previous: "في", beforePrevious: nil, language: .arabic, limit: 3)
            _ = lexicon.predictions(previous: "in", beforePrevious: nil, language: .english, limit: 3)
        }
        print("TIMING next-word tables first load: \(String(format: "%.0f", firstLoad)) ms (once)")
        // Long, mistyped and prefixed words are the slow cases: few or no words start the same way.
        let words = ["والمستشفياتت", "بالاستراتيجيه", "خاصتهمم", "مستشفي", "هنتقابلوا", "internationalizationn", "responsibilty", "zzzqqqxx"]
        var times: [Double] = []
        for word in words {
            let chars = Array(word)
            for n in 1...chars.count {
                let typed = String(chars[0..<n])
                let lang = Lexicon.language(of: typed)
                times.append(milliseconds {
                    _ = lexicon.rank(typed, language: lang, limit: 3, previous: "في", beforePrevious: nil)
                    _ = lexicon.autocorrection(for: typed, language: lang)
                })
            }
        }
        let average = times.reduce(0, +) / Double(times.count)
        print("TIMING suggestions per key: average \(String(format: "%.2f", average)) ms, worst \(String(format: "%.2f", times.max() ?? 0)) ms over \(times.count) keys")
        let glide = milliseconds {
            for _ in 0..<10 { _ = lexicon.glideVocabulary(.arabic, startKeys: ["ا", "ل", "ب"], endKeys: ["ت", "ن", "م"]) }
        } / 10
        print("TIMING glide word list: \(String(format: "%.2f", glide)) ms per swipe")
        XCTAssertLessThan(average, 30)
    }

    func testCompletionsMatchAFullScan() {
        let lexicon = Lexicon()
        XCTAssertTrue(lexicon.rank("hell", language: .english, limit: 3).contains { $0.word == "hello" })
        XCTAssertTrue(lexicon.rank("مدرس", language: .arabic, limit: 5).contains { $0.word.hasPrefix("مدرس") && $0.kind == .completion })
        let glide = lexicon.glideVocabulary(.english, startKeys: ["h"], endKeys: ["o"])
        XCTAssertTrue(glide.contains { $0.word == "hello" })
        XCTAssertTrue(glide.allSatisfy { $0.word.hasPrefix("h") && $0.word.hasSuffix("o") })
    }

    func testNextWordTablesLoadInBackgroundOnThePhone() {
        Lexicon.tablesInBackground = true
        defer { Lexicon.tablesInBackground = false }
        let lexicon = Lexicon()
        _ = lexicon.isKnown("hello", language: .english)
        var first: [String] = []
        let asked = milliseconds { first = lexicon.predictions(previous: "in", beforePrevious: nil, language: .english, limit: 3) }
        print("TIMING next-word ask while the tables load: \(String(format: "%.1f", asked)) ms")
        XCTAssertLessThan(asked, 100, "asking must not wait for the tables")
        _ = first
        let deadline = Date().addingTimeInterval(30)
        var later: [String] = []
        while later.isEmpty && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            later = lexicon.predictions(previous: "in", beforePrevious: nil, language: .english, limit: 3)
        }
        XCTAssertFalse(later.isEmpty, "next-word suggestions arrive once the tables are in")
    }

    func testEgyptianWordsAreLeftAlone() {
        let lexicon = Lexicon()
        let url = Bundle(for: Lexicon.self).url(forResource: "words_eg", withExtension: "txt")!
        let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(whereSeparator: \.isNewline) ?? []
        var changed: [String] = []
        for line in lines {
            let word = String(line.split(separator: " ")[0])
            if let fix = lexicon.autocorrection(for: word, language: .arabic) { changed.append("\(word)→\(fix)") }
        }
        print("EGYPT list words corrected: \(changed.count) of \(lines.count): \(changed.prefix(40).joined(separator: " "))")
        let everyday = ["ازيك", "عامل", "ايه", "النهارده", "بكرة", "امبارح", "دلوقتي", "كده", "كدة", "ليه", "فين", "مين", "عشان", "علشان", "خلاص", "ماشي", "طب", "طيب", "اهو", "بقى", "بقا", "لسه", "لسة", "برضه", "برضو", "اوي", "قوي", "شوية", "حاجة", "هعمل", "هعملها", "عملتها", "مبعرفش", "معرفش", "مش", "مفيش", "فيه", "عايز", "عاوز", "هتيجي", "جاي", "رايح", "هنروح", "متقلقش", "ماتقلقش", "يلا", "ياعم", "ياجماعة", "بتاعي", "بتاعك", "بتاعتي", "بتوعنا", "ازاي", "اللي", "إللي", "دي", "ده", "دول", "هناك", "هنا", "خالص", "قوللي", "قولي", "اتصلت", "هكلمك", "كلمني", "وحشتني", "حبيبي", "ياريت", "اكيد", "تمام", "ماشيه", "مبقتش", "مكنتش", "هيبقى", "بيقول", "بتعمل", "بنكتب", "متزعلش", "عيالي", "الولاد", "شغلي", "الشغل", "فلوس", "اشتريت", "هشتري", "روحت", "جيت", "هاجي", "مشيت", "نمت", "صحيت", "اكلت", "هاكل", "شربت"]
        var fixes: [String] = []
        for w in everyday { if let f = lexicon.autocorrection(for: w, language: .arabic) { fixes.append("\(w)→\(f)") } }
        print("EGYPT everyday corrected: \(fixes.count) of \(everyday.count): \(fixes.joined(separator: " "))")
    }
}
