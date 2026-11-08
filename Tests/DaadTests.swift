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
}
