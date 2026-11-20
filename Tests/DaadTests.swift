import XCTest
import UIKit

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

    // MARK: Memory (prints how much each part of the word data takes; keyboards have a tight budget)

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    func testMemoryFootprint() {
        let lexicon = Lexicon()
        var last = footprintMB()
        func step(_ name: String, _ work: () -> Void) {
            work()
            let now = footprintMB()
            print("MEMORY \(name): +\(String(format: "%.1f", now - last)) MB (total \(String(format: "%.1f", now)) MB)")
            last = now
        }
        step("arabic words") { _ = lexicon.isKnown("خلصت", language: .arabic) }
        step("english words") { _ = lexicon.isKnown("hello", language: .english) }
        step("arabic suggestions") { _ = lexicon.rank("خاصت", language: .arabic, limit: 3) }
        step("franco index") { _ = lexicon.francoCandidates("ezayak", limit: 3) }
        step("next words") {
            _ = lexicon.predictions(previous: "انا", beforePrevious: nil, language: .arabic, limit: 3)
            _ = lexicon.predictions(previous: "i", beforePrevious: nil, language: .english, limit: 3)
        }
        step("glide vocabulary") {
            _ = lexicon.glideVocabulary(.arabic, startKeys: ["ا", "ل", "ب"], endKeys: ["ت", "ن", "م"])
            _ = lexicon.glideVocabulary(.english, startKeys: ["t", "r", "y"], endKeys: ["e", "r", "w"])
        }
    }

    // MARK: Speed (what one key press costs; everything here runs on the thread that draws the keys)

    private func milliseconds(_ work: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        work()
        return (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    func testSpeedOfSuggestions() {
        let lexicon = Lexicon()
        _ = lexicon.isKnown("خلصت", language: .arabic)
        _ = lexicon.isKnown("hello", language: .english)
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
        XCTAssertLessThan(average, 30, "suggestions must stay far below a frame budget even in a debug build")
    }

    func testCompletionsMatchAFullScan() {
        // The prefix index must give the same words a walk over the whole list gave.
        let lexicon = Lexicon()
        XCTAssertEqual(lexicon.rank("hel", language: .english, limit: 3).first?.word, "hello")
        XCTAssertTrue(lexicon.rank("مدرس", language: .arabic, limit: 5).contains { $0.word.hasPrefix("مدرس") && $0.kind == .completion })
        // Hamza variants are found through the same index ("انا" typed, "أنا" exists).
        XCTAssertTrue(lexicon.isKnown("أنا", language: .arabic) || lexicon.isKnown("انا", language: .arabic))
        XCTAssertFalse(lexicon.glideVocabulary(.english, startKeys: ["h"], endKeys: ["o"]).filter { $0.word == "hello" }.isEmpty)
        XCTAssertTrue(lexicon.glideVocabulary(.english, startKeys: ["h"], endKeys: ["o"]).allSatisfy { $0.word.hasPrefix("h") && $0.word.hasSuffix("o") })
    }

    func testWordListsLoadInBackgroundOnThePhone() {
        Lexicon.loadsInBackground = true
        defer { Lexicon.loadsInBackground = false }
        let lexicon = Lexicon()
        let loaded = expectation(description: "word list arrives")
        loaded.assertForOverFulfill = false
        lexicon.onLoad = { loaded.fulfill() }
        // Asking before the list is there answers at once with nothing, and never blocks.
        XCTAssertLessThan(milliseconds { _ = lexicon.rank("hel", language: .english, limit: 3) }, 50)
        wait(for: [loaded], timeout: 60)
        XCTAssertEqual(lexicon.rank("hel", language: .english, limit: 3).first?.word, "hello")
    }

    func testMemoryOfScreens() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        var last = footprintMB()
        func measure(_ name: String, _ make: () -> UIView) {
            autoreleasepool {
                let v = make()
                v.frame = CGRect(x: 0, y: 0, width: 393, height: 300)
                window.addSubview(v)
                v.setNeedsLayout(); v.layoutIfNeeded()
                _ = UIGraphicsImageRenderer(bounds: v.bounds).image { _ in v.drawHierarchy(in: v.bounds, afterScreenUpdates: true) }
                let now = footprintMB()
                print("MEMORY screen \(name): +\(String(format: "%.1f", now - last)) MB (total \(String(format: "%.1f", now)) MB)")
                last = now
            }
        }
        measure("keys (arabic)") {
            let k = KeyboardView()
            k.configure(rows: Layouts.build(context(.arabic)).rows, maxUnits: 11.6, theme: .make(dark: true))
            return k
        }
        measure("keys (english)") {
            let k = KeyboardView()
            k.configure(rows: Layouts.build(context(.english)).rows, maxUnits: 10, theme: .make(dark: true))
            return k
        }
        measure("suggestion bar") { SuggestionBarView() }
        measure("emoji") { EmojiPanelView() }
        measure("clipboard") { ClipboardPanelView() }
        measure("tools") { ToolsPanelView() }
        measure("calculator") { CalculatorPanelView() }
        measure("settings") { SettingsPanelView() }
        measure("search") { SearchPanelView() }
        measure("look") { LookPanelView() }
        measure("edit") { EditPanelView() }
        measure("whole keyboard") {
            let vc = KeyboardViewController()
            vc.loadViewIfNeeded()
            return vc.view
        }
    }

    /// Splits the first typing session into steps, to find what the one-time jump is made of.
    func testMemoryFirstTypingSteps() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        let vc = KeyboardViewController()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 552, width: 393, height: 300)
        window.addSubview(vc.view)
        vc.viewWillAppear(false)
        vc.view.layoutIfNeeded()
        let dummy = KeyboardView()
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
        settle()
        var last = footprintMB()
        func step(_ name: String, _ body: () -> Void) {
            autoreleasepool { body() }
            settle()
            let now = footprintMB()
            print("MEMORY step \(name): +\(String(format: "%.1f", now - last)) MB (total \(String(format: "%.1f", now)) MB)")
            last = now
        }
        func type(_ w: String) {
            for ch in w { vc.keyboardView(dummy, didTap: .character(String(ch))) }
            vc.keyboardView(dummy, didTap: .space)
        }
        print("MEMORY step start: total \(String(format: "%.1f", last)) MB")
        step("first letter") { vc.keyboardView(dummy, didTap: .character("h")) }
        step("rest of first word") { for ch in "ello" { vc.keyboardView(dummy, didTap: .character(String(ch))) } }
        step("first space") { vc.keyboardView(dummy, didTap: .space) }
        step("english words x20") { for _ in 0..<20 { type("the"); type("meeting"); type("ok") } }
        step("switch language 1") { vc.keyboardViewSwitchLanguage(dummy, forward: true) }
        step("first arabic word") { type("ازيك") }
        step("arabic words x20") { for _ in 0..<20 { type("خلصت"); type("بكرة"); type("تمام") } }
        step("switch language 2") { vc.keyboardViewSwitchLanguage(dummy, forward: true) }
        step("dual words x20") { for _ in 0..<20 { type("hello"); type("ازيك") } }
        step("switch language 3") { vc.keyboardViewSwitchLanguage(dummy, forward: true) }
        step("shift + delete x20") { for _ in 0..<20 { vc.keyboardView(dummy, didTap: .shift); vc.keyboardViewDeleteBackward(dummy, word: false) } }
        step("language cycle x20") { for _ in 0..<20 { vc.keyboardViewSwitchLanguage(dummy, forward: true) } }
        step("mixed again x20") { for _ in 0..<20 { type("hello"); type("ازيك"); vc.keyboardViewSwitchLanguage(dummy, forward: true) } }
        step("memory warning") { vc.didReceiveMemoryWarning() }
    }

    func testMemoryWhileTyping() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.isHidden = false
        let vc = KeyboardViewController()
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 552, width: 393, height: 300)
        window.addSubview(vc.view)
        vc.viewWillAppear(false)
        vc.view.layoutIfNeeded()
        let dummy = KeyboardView()
        let words = ["hello", "ازيك", "the", "خلصت", "meeting", "بكرة", "ok", "تمام"]
        var start = footprintMB()
        for round in 1...6 {
            autoreleasepool {
                for _ in 0..<20 {
                    for w in words {
                        for ch in w { vc.keyboardView(dummy, didTap: .character(String(ch))) }
                        vc.keyboardView(dummy, didTap: .space)
                        RunLoop.current.run(until: Date().addingTimeInterval(0.002))   // let UIKit settle, like a phone
                    }
                    vc.keyboardView(dummy, didTap: .shift)
                    vc.keyboardViewSwitchLanguage(dummy, forward: true)
                    vc.keyboardViewDeleteBackward(dummy, word: false)
                }
                vc.view.layoutIfNeeded()
            }
            let now = footprintMB()
            print("MEMORY typing round \(round): +\(String(format: "%.1f", now - start)) MB (total \(String(format: "%.1f", now)) MB)")
            if round == 1 { start = now }
        }
    }
}
