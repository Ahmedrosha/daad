import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    private let suggestionBar = SuggestionBarView()
    private let keyboardView = KeyboardView()
    private let emojiPanel = EmojiPanelView()
    private let clipboardPanel = ClipboardPanelView()
    private var heightConstraint: NSLayoutConstraint?
    private let settings = SharedSettings.shared
    private let lexicon = Lexicon.shared
    private let clipboard = ClipboardStore()

    private enum Panel { case keys, emoji, clipboard }
    private var panel: Panel = .keys

    private var language: DaadLanguage = .arabic
    private var mode: KeyboardMode = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap: Date?
    private var lastSpaceTap: Date?
    private var currentContext: LayoutContext?
    private var rowCount = 4

    /// The last autocorrect, so an immediate backspace can undo it.
    private var lastCorrection: (original: String, replacement: String)?
    /// Other candidates for the word just produced by glide typing.
    private var glideAlternatives: [String] = []
    private var lastGlideWord: String?

    private let barHeight: CGFloat = 42
    private let recentsKey = "recentEmojis"

    private lazy var tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private lazy var tickHaptic = UISelectionFeedbackGenerator()

    private var store: UserDefaults {
        hasFullAccess ? (SharedSettings.store ?? .standard) : .standard
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        language = settings.language
        lexicon.configure(store: store)
        clipboard.configure(store: store)

        keyboardView.delegate = self
        for v in [suggestionBar, keyboardView, emojiPanel, clipboardPanel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            suggestionBar.heightAnchor.constraint(equalToConstant: barHeight),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        for p in [emojiPanel, clipboardPanel] as [UIView] {
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                p.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                p.topAnchor.constraint(equalTo: view.topAnchor),
                p.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            p.isHidden = true
        }
        wireBars()
        reload(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mode = .letters
        showPanel(.keys)
        if hasFullAccess && settings.consumeClearLearnedRequest() { lexicon.clearLearned() }
        if hasFullAccess { clipboard.captureIfChanged() }
        updateAutoShift()
        reload(force: true)   // picks up changes made in the app's Settings screen
        if settings.bool(.haptics) && hasFullAccess { tapHaptic.prepare() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowImmediateTouches()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lexicon.flush()
    }

    /// iOS holds back touches near the bottom edge (home-indicator gesture), so a long press on the
    /// space bar never arrived until the finger lifted. Turning that delay off fixes long presses there.
    private func allowImmediateTouches() {
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
        var current: UIView? = view
        while let v = current {
            v.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
            current = v.superview
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.updateHeight() })
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if hasFullAccess { clipboard.captureIfChanged() }
        updateAutoShift()
        reload()
    }

    // MARK: Bars and panels

    private func wireBars() {
        suggestionBar.onDismiss = { [weak self] in self?.dismissKeyboard() }
        suggestionBar.onEmoji = { [weak self] in self?.showPanel(.emoji) }
        suggestionBar.onClipboard = { [weak self] in self?.showPanel(.clipboard) }
        suggestionBar.onSuggestion = { [weak self] value in self?.applySuggestion(value) }

        emojiPanel.onInsert = { [weak self] emoji in
            guard let self else { return }
            self.feedback(for: .character(emoji))
            self.textDocumentProxy.insertText(emoji)
            self.addRecent(emoji)
        }
        emojiPanel.onBackspace = { [weak self] in
            self?.feedback(for: .backspace)
            self?.textDocumentProxy.deleteBackward()
        }
        emojiPanel.onClose = { [weak self] in self?.showPanel(.keys) }

        clipboardPanel.onInsert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
            self?.showPanel(.keys)
        }
        clipboardPanel.onDelete = { [weak self] index in
            self?.clipboard.remove(at: index)
            self?.configureClipboardPanel()
        }
        clipboardPanel.onClear = { [weak self] in
            self?.clipboard.clear()
            self?.configureClipboardPanel()
        }
        clipboardPanel.onClose = { [weak self] in self?.showPanel(.keys) }
    }

    private func showPanel(_ newPanel: Panel) {
        panel = newPanel
        let theme = KeyboardTheme.make(dark: isDark)
        switch newPanel {
        case .keys:
            break
        case .emoji:
            emojiPanel.configure(theme: theme, recents: recents, closeTitle: language == .arabic ? "أبج" : "ABC")
        case .clipboard:
            if hasFullAccess { clipboard.captureIfChanged() }
            configureClipboardPanel()
        }
        emojiPanel.isHidden = newPanel != .emoji
        clipboardPanel.isHidden = newPanel != .clipboard
        suggestionBar.isHidden = newPanel != .keys
        keyboardView.isHidden = newPanel != .keys
        if newPanel == .keys { updateSuggestions() }
    }

    private func configureClipboardPanel() {
        clipboardPanel.configure(theme: .make(dark: isDark), items: clipboard.items,
                                 arabic: language == .arabic, fullAccess: hasFullAccess)
    }

    private var recents: [String] { store.stringArray(forKey: recentsKey) ?? [] }

    private func addRecent(_ emoji: String) {
        var list = recents
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        store.set(Array(list.prefix(32)), forKey: recentsKey)
    }

    // MARK: Layout

    private var isDark: Bool {
        if textDocumentProxy.keyboardAppearance == .dark { return true }
        return traitCollection.userInterfaceStyle == .dark
    }

    private var returnLabel: String {
        let arabic = language == .arabic
        switch textDocumentProxy.returnKeyType ?? .default {
        case .search, .google, .yahoo: return arabic ? "بحث" : "search"
        case .go, .route: return arabic ? "انتقال" : "go"
        case .send: return arabic ? "إرسال" : "send"
        case .done: return arabic ? "تم" : "done"
        case .next: return arabic ? "التالي" : "next"
        case .join: return arabic ? "انضمام" : "join"
        default: return ""
        }
    }

    private func reload(force: Bool = false) {
        let context = LayoutContext(
            language: language,
            mode: mode,
            shift: shift,
            showNumberRow: settings.bool(.numberRow),
            arabicDigits: settings.bool(.arabicDigits),
            needsGlobe: needsInputModeSwitchKey,
            returnLabel: returnLabel,
            dark: isDark)
        if force || context != currentContext {
            currentContext = context
            let layout = Layouts.build(context)
            rowCount = layout.rows.count
            let theme = KeyboardTheme.make(dark: context.dark)
            keyboardView.configure(rows: layout.rows, maxUnits: layout.maxUnits, theme: theme)
            suggestionBar.apply(theme: theme)
            updateHeight()
        }
        keyboardView.glideEnabled = mode == .letters && settings.bool(.glideTyping)
        updateSuggestions()
    }

    private func updateHeight() {
        let screen = UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let rowHeight: CGFloat = landscape ? 40 : 52
        let height = barHeight + CGFloat(rowCount) * rowHeight + 6
        if let c = heightConstraint {
            c.constant = height
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: height)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: Words

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    /// The letters right before the cursor (the word being typed).
    private var currentWord: String {
        guard let before = proxy.documentContextBeforeInput else { return "" }
        var word = ""
        for ch in before.reversed() {
            guard ch.isLetter || ch == "'" || isMark(ch) else { break }
            word.insert(ch, at: word.startIndex)
        }
        return word
    }

    private func isMark(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { $0.properties.generalCategory == .nonspacingMark }
    }

    private func updateSuggestions() {
        guard panel == .keys else { return }
        let word = currentWord
        if let glided = lastGlideWord, glided != word {
            lastGlideWord = nil
            glideAlternatives = []
        }
        guard settings.bool(.suggestions), !word.isEmpty else {
            suggestionBar.showTools()
            return
        }
        if lastGlideWord == word, glideAlternatives.count > 1 {
            let alts = glideAlternatives.filter { $0 != word }.prefix(2)
            var items = [Suggestion(title: word, value: word, primary: true)]
            items += alts.map { Suggestion(title: $0, value: $0, primary: false) }
            suggestionBar.show(arrange(items))
            return
        }

        let lang = Lexicon.language(of: word)
        let known = lexicon.isKnown(word, language: lang)
        let completions = lexicon.completions(for: word, language: lang, limit: 3)
        let fixes = known ? [] : lexicon.corrections(for: word, language: lang, limit: 2)

        var items: [Suggestion] = []
        if let fix = fixes.first, settings.bool(.autocorrect) {
            // Middle = what space will apply; the typed word stays available in quotes.
            items.append(Suggestion(title: fix, value: fix, primary: true))
            items.append(Suggestion(title: "\"\(word)\"", value: word, primary: false))
            if let c = completions.first(where: { $0 != fix }) ?? fixes.dropFirst().first {
                items.append(Suggestion(title: c, value: c, primary: false))
            }
        } else {
            var pool = known ? [word] : []
            pool += fixes
            pool += completions
            var seen = Set<String>()
            for w in pool where seen.insert(w.lowercased()).inserted {
                items.append(Suggestion(title: w, value: w, primary: false))
                if items.count == 3 { break }
            }
            if items.isEmpty { items = [Suggestion(title: "\"\(word)\"", value: word, primary: false)] }
        }
        suggestionBar.show(arrange(items))
    }

    /// Puts the most likely item in the middle slot, like Gboard.
    private func arrange(_ items: [Suggestion]) -> [Suggestion] {
        guard items.count == 3 else { return items }
        return [items[1], items[0], items[2]]
    }

    private func applySuggestion(_ value: String) {
        let word = currentWord
        for _ in 0..<word.count { proxy.deleteBackward() }
        proxy.insertText(value + " ")
        lexicon.learn(value)
        lastCorrection = nil
        lastGlideWord = nil
        glideAlternatives = []
        feedback(for: .character(value))
        if shift == .on { shift = .off }
        updateAutoShift()
        reload()
    }

    /// Before a space or new line: learn the word, or fix it when autocorrect is on.
    private func commitCurrentWord() {
        let word = currentWord
        lastCorrection = nil
        guard !word.isEmpty else { return }
        let lang = Lexicon.language(of: word)
        if settings.bool(.autocorrect), lastGlideWord != word,
           !lexicon.isKnown(word, language: lang),
           let fix = lexicon.corrections(for: word, language: lang, limit: 1).first {
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(fix)
            lastCorrection = (word, fix)
            lexicon.learn(fix)
        } else {
            lexicon.learn(word)
        }
    }

    // MARK: Text helpers

    private func insert(_ text: String) {
        if language == .arabic, settings.bool(.rtlMark),
           (proxy.documentContextBeforeInput ?? "").isEmpty,
           (proxy.documentContextAfterInput ?? "").isEmpty {
            proxy.insertText("\u{200F}")
        }
        if let first = text.first, !first.isLetter { commitWordBeforePunctuation() }
        proxy.insertText(text)
        lastCorrection = nil
        if shift == .on { shift = .off }
        updateAutoShift()
        reload()
    }

    private func commitWordBeforePunctuation() {
        let word = currentWord
        if !word.isEmpty { lexicon.learn(word) }
    }

    private func updateAutoShift() {
        guard shift != .locked else { return }
        shift = shouldAutoCapitalize() ? .on : .off
    }

    private func shouldAutoCapitalize() -> Bool {
        guard language == .english, mode == .letters, settings.bool(.autoCapitalize) else { return false }
        let type = proxy.autocapitalizationType ?? .sentences
        let before = proxy.documentContextBeforeInput ?? ""
        switch type {
        case .none: return false
        case .allCharacters: return true
        case .words:
            return before.isEmpty || (before.last?.isWhitespace ?? true)
        default:
            if before.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            if before.hasSuffix("\n") { return true }
            guard before.last == " " else { return false }
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            guard let last = trimmed.last else { return true }
            return ".!?".contains(last)
        }
    }

    private func deleteWord() {
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            proxy.deleteBackward()
            return
        }
        var chars = Array(before)
        var count = 0
        while let last = chars.last, last.isWhitespace { chars.removeLast(); count += 1 }
        while let last = chars.last, !last.isWhitespace { chars.removeLast(); count += 1 }
        for _ in 0..<max(count, 1) { proxy.deleteBackward() }
    }

    private func handleSpace() {
        let before = proxy.documentContextBeforeInput ?? ""
        let now = Date()
        if settings.bool(.quickPeriod),
           let last = lastSpaceTap, now.timeIntervalSince(last) < 0.45,
           before.hasSuffix(" "),
           let previous = before.dropLast().last,
           !previous.isWhitespace,
           !".!?؟،,".contains(previous) {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpaceTap = nil
            lastCorrection = nil
        } else {
            commitCurrentWord()
            proxy.insertText(" ")
            lastSpaceTap = now
        }
        lastGlideWord = nil
        glideAlternatives = []
        if mode != .letters { mode = .letters }
        updateAutoShift()
        reload()
    }

    private func handleShift() {
        let now = Date()
        if let last = lastShiftTap, now.timeIntervalSince(last) < 0.3 {
            shift = .locked
            lastShiftTap = nil
        } else {
            shift = (shift == .off) ? .on : .off
            lastShiftTap = now
        }
        reload()
    }

    private func feedback(for action: KeyAction) {
        if settings.bool(.keySound) {
            if hasFullAccess {
                let sound: SystemSoundID
                switch action {
                case .backspace, .forwardDelete: sound = 1155
                case .character, .space: sound = 1104
                default: sound = 1156
                }
                AudioServicesPlaySystemSound(sound)
            } else {
                UIDevice.current.playInputClick()
            }
        }
        if settings.bool(.haptics) && hasFullAccess {
            tapHaptic.impactOccurred()
            tapHaptic.prepare()
        }
    }
}

// MARK: - KeyboardViewDelegate

extension KeyboardViewController: KeyboardViewDelegate {
    var nextLanguageName: String { language.toggled.displayName }
    var popupsEnabled: Bool { settings.bool(.keyPopups) }

    func keyboardView(_ view: KeyboardView, didTap action: KeyAction) {
        switch action {
        case .character(let text):
            insert(text)
        case .space:
            handleSpace()
        case .returnKey:
            commitCurrentWord()
            proxy.insertText("\n")
            lastCorrection = nil
            updateAutoShift()
            reload()
        case .shift:
            handleShift()
        case .modeChange(let newMode):
            mode = newMode
            updateAutoShift()
            reload()
        case .nextKeyboard:
            advanceToNextInputMode()
        case .dismiss:
            dismissKeyboard()
        case .forwardDelete:
            guard let after = proxy.documentContextAfterInput, let next = after.first else { return }
            proxy.adjustTextPosition(byCharacterOffset: next.utf16.count)
            proxy.deleteBackward()
            reload()
        case .backspace:
            break
        }
    }

    func keyboardView(_ view: KeyboardView, insertAlternate text: String) {
        insert(text)
    }

    func keyboardViewDeleteBackward(_ view: KeyboardView, word: Bool) {
        // Backspace right after an autocorrect brings back what was typed.
        if !word, let c = lastCorrection, (proxy.documentContextBeforeInput ?? "").hasSuffix(c.replacement + " ") {
            for _ in 0..<(c.replacement.count + 1) { proxy.deleteBackward() }
            proxy.insertText(c.original)
            lastCorrection = nil
            reload()
            return
        }
        lastCorrection = nil
        if word { deleteWord() } else { proxy.deleteBackward() }
        updateAutoShift()
        reload()
    }

    func keyboardViewSwitchLanguage(_ view: KeyboardView) {
        language = language.toggled
        settings.language = language
        mode = .letters
        updateAutoShift()
        reload()
    }

    func keyboardView(_ view: KeyboardView, moveCursorBy steps: Int) {
        // Finger to the right should move the cursor visually right; in Arabic text that is backwards.
        let nearby = proxy.documentContextBeforeInput?.last ?? proxy.documentContextAfterInput?.first
        let rightToLeft = nearby.map(TextHelpers.isArabic) ?? (language == .arabic)
        proxy.adjustTextPosition(byCharacterOffset: rightToLeft ? -steps : steps)
    }

    func keyboardView(_ view: KeyboardView, feedbackFor action: KeyAction) {
        feedback(for: action)
    }

    func keyboardViewTickFeedback(_ view: KeyboardView) {
        if settings.bool(.haptics) && hasFullAccess { tickHaptic.selectionChanged() }
    }

    func keyboardView(_ view: KeyboardView, didGlide path: [CGPoint], keyCenters: [Character: CGPoint], keyWidth: CGFloat) {
        var results = GlideDecoder.decode(path: path, keyCenters: keyCenters, keyWidth: keyWidth,
                                          language: language, lexicon: lexicon)
        guard !results.isEmpty else { return }
        if language == .english && shift != .off {
            results = results.map { shift == .locked ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        let word = results[0]
        // Glided words are separated automatically, like Gboard.
        if let last = proxy.documentContextBeforeInput?.last, !last.isWhitespace, !"([{\"'«".contains(last) {
            proxy.insertText(" ")
        }
        proxy.insertText(word)
        lastCorrection = nil
        lastGlideWord = word
        glideAlternatives = results
        if shift == .on { shift = .off }
        keyboardViewTickFeedback(view)
        reload()
    }
}
