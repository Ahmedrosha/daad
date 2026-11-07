import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    private let suggestionBar = SuggestionBarView()
    private let keyboardView = KeyboardView()
    private let emojiPanel = EmojiPanelView()
    private let clipboardPanel = ClipboardPanelView()
    private let toolsPanel = ToolsPanelView()
    private let calculatorPanel = CalculatorPanelView()
    private let settingsPanel = SettingsPanelView()
    private let searchPanel = SearchPanelView()
    private let lookPanel = LookPanelView()
    private var heightConstraint: NSLayoutConstraint?
    private var barHeightConstraint: NSLayoutConstraint?
    private var keyboardLeading: NSLayoutConstraint!
    private var keyboardTrailing: NSLayoutConstraint!
    /// Buttons beside the shrunken keyboard in one-handed mode.
    private let oneHandedStrip = UIStackView()
    private let switchSideButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let settings = SharedSettings.shared
    private let lexicon = Lexicon.shared
    private let clipboard = ClipboardStore()

    private enum Panel { case keys, emoji, clipboard, tools, calculator, settings, look, contacts, translate }
    private var panel: Panel = .keys
    /// Contacts search and translation are typed with the keyboard's own keys.
    private var isSearching: Bool { panel == .contacts || panel == .translate }
    private var query = ""
    private var translateWork: DispatchWorkItem?
    private let searchHeight: CGFloat = 190

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
    /// Shortcuts from the app plus the iPhone's own Text Replacements.
    private var textShortcuts: [String: String] = [:]
    private var systemShortcuts: [String: String] = [:]

    private lazy var tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private lazy var tickHaptic = UISelectionFeedbackGenerator()

    private var store: UserDefaults {
        hasFullAccess ? (SharedSettings.store ?? .standard) : .standard
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        language = settings.language
        // Tells the app which language is being typed, so it lays the text out the right way.
        primaryLanguage = language == .arabic ? "ar" : "en-US"
        lexicon.configure(store: store)
        clipboard.configure(store: store)

        keyboardView.delegate = self
        keyboardLeading = keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        keyboardTrailing = keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let overlays: [UIView] = [emojiPanel, clipboardPanel, toolsPanel, calculatorPanel, settingsPanel, lookPanel]
        for v in [suggestionBar, keyboardView, searchPanel] + overlays {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor),
            searchPanel.leadingAnchor.constraint(equalTo: suggestionBar.leadingAnchor),
            searchPanel.trailingAnchor.constraint(equalTo: suggestionBar.trailingAnchor),
            searchPanel.topAnchor.constraint(equalTo: suggestionBar.topAnchor),
            searchPanel.bottomAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardLeading,
            keyboardTrailing,
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let barConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: barHeight)
        barConstraint.isActive = true
        barHeightConstraint = barConstraint
        searchPanel.isHidden = true
        for p in overlays {
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                p.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                p.topAnchor.constraint(equalTo: view.topAnchor),
                p.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            p.isHidden = true
        }
        wireBars()
        setUpOneHandedStrip()
        requestSupplementaryLexicon { [weak self] lexicon in
            var map: [String: String] = [:]
            for entry in lexicon.entries where entry.userInput != entry.documentText {
                map[entry.userInput] = entry.documentText
            }
            self?.systemShortcuts = map
            self?.refreshShortcuts()
        }
        refreshShortcuts()
        reload(force: true)
    }

    private func refreshShortcuts() {
        textShortcuts = systemShortcuts.merging(settings.shortcuts) { _, mine in mine }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mode = .letters
        showPanel(.keys)
        if hasFullAccess && settings.consumeClearLearnedRequest() { lexicon.clearLearned() }
        if hasFullAccess { clipboard.captureIfChanged() }
        refreshShortcuts()
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
        suggestionBar.onTools = { [weak self] in self?.showPanel(.tools) }
        suggestionBar.onCalculator = { [weak self] in self?.showPanel(.calculator) }
        suggestionBar.onLanguage = { [weak self] in
            guard let self else { return }
            self.keyboardViewSwitchLanguage(self.keyboardView)
        }
        lookPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        lookPanel.onChange = { [weak self] in
            guard let self else { return }
            self.reload(force: true)
            self.view.setNeedsLayout()
        }

        toolsPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        toolsPanel.onSelect = { [weak self] tool in
            guard let self else { return }
            switch tool {
            case .emoji: self.showPanel(.emoji)
            case .clipboard: self.showPanel(.clipboard)
            case .translate: self.showPanel(.translate)
            case .calculator: self.showPanel(.calculator)
            case .contacts: self.showPanel(.contacts)
            case .oneHanded:
                self.settings.oneHandedMode = self.settings.oneHandedMode == "off" ? "right" : "off"
                self.showPanel(.keys)
            case .look: self.showPanel(.look)
            case .settings: self.showPanel(.settings)
            }
        }
        calculatorPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        calculatorPanel.onInsert = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
            self?.showPanel(.keys)
        }
        settingsPanel.onClose = { [weak self] in
            self?.showPanel(.keys)
            self?.reload(force: true)
        }
        settingsPanel.onChange = { [weak self] in self?.reload(force: true) }
        settingsPanel.onOpenLook = { [weak self] in self?.showPanel(.look) }
        searchPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        searchPanel.onInsert = { [weak self] text in
            guard let self else { return }
            self.textDocumentProxy.insertText(text)
            self.showPanel(.keys)
        }
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
        clipboardPanel.onPin = { [weak self] index in
            self?.clipboard.pin(at: index)
            self?.configureClipboardPanel()
        }
        clipboardPanel.onUnpin = { [weak self] index in
            self?.clipboard.unpin(at: index)
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
        let arabic = language == .arabic
        translateWork?.cancel()
        switch newPanel {
        case .keys:
            break
        case .tools:
            toolsPanel.configure(theme: theme, arabic: arabic)
        case .calculator:
            calculatorPanel.configure(theme: theme, arabic: arabic)
        case .settings:
            settingsPanel.configure(theme: theme, arabic: arabic)
        case .look:
            lookPanel.configure(theme: theme, arabic: arabic)
        case .contacts:
            query = ""
            mode = .letters
            searchPanel.configure(theme: theme, title: arabic ? "جهات الاتصال" : "Contacts", insertTitle: nil)
        case .translate:
            query = ""
            mode = .letters
            searchPanel.configure(theme: theme, title: arabic ? "ترجمة" : "Translate", insertTitle: arabic ? "إدراج" : "Insert")
        case .emoji:
            emojiPanel.configure(theme: theme, recents: recents, closeTitle: language == .arabic ? "أبج" : "ABC")
        case .clipboard:
            if hasFullAccess { clipboard.captureIfChanged() }
            configureClipboardPanel()
        }
        emojiPanel.isHidden = newPanel != .emoji
        clipboardPanel.isHidden = newPanel != .clipboard
        toolsPanel.isHidden = newPanel != .tools
        calculatorPanel.isHidden = newPanel != .calculator
        settingsPanel.isHidden = newPanel != .settings
        lookPanel.isHidden = newPanel != .look
        searchPanel.isHidden = !isSearching
        suggestionBar.isHidden = newPanel != .keys
        keyboardView.isHidden = !(newPanel == .keys || isSearching)
        barHeightConstraint?.constant = isSearching ? searchHeight : barHeight
        updateHeight()
        if isSearching { reload(force: true); updateSearch() }
        if newPanel == .keys { reload() }
        view.setNeedsLayout()
    }

    // MARK: One-handed mode

    private func setUpOneHandedStrip() {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        switchSideButton.setImage(UIImage(systemName: "arrow.left.and.right", withConfiguration: config), for: .normal)
        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: config), for: .normal)
        switchSideButton.addTarget(self, action: #selector(switchOneHandedSide), for: .touchUpInside)
        expandButton.addTarget(self, action: #selector(exitOneHanded), for: .touchUpInside)
        oneHandedStrip.axis = .vertical
        oneHandedStrip.distribution = .fillEqually
        oneHandedStrip.addArrangedSubview(expandButton)
        oneHandedStrip.addArrangedSubview(switchSideButton)
        view.addSubview(oneHandedStrip)
    }

    @objc private func switchOneHandedSide() {
        settings.oneHandedMode = settings.oneHandedMode == "right" ? "left" : "right"
        view.setNeedsLayout()
    }

    @objc private func exitOneHanded() {
        settings.oneHandedMode = "off"
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let mode = settings.oneHandedMode
        let active = mode != "off" && (panel == .keys || isSearching)
        let gap = active ? floor(view.bounds.width * 0.16) : 0
        var leading = mode == "right" ? gap : 0
        var trailing = mode == "left" ? -gap : 0
        if !active && (panel == .keys || isSearching) {
            // Narrower keyboard, centered.
            let scale = CGFloat(min(max(settings.keyboardWidthScale, 0.7), 1))
            let inset = floor(view.bounds.width * (1 - scale) / 2)
            leading = inset
            trailing = -inset
        }
        if keyboardLeading.constant != leading || keyboardTrailing.constant != trailing {
            keyboardLeading.constant = leading
            keyboardTrailing.constant = trailing
            keyboardView.setNeedsLayout()
        }
        oneHandedStrip.isHidden = !active
        let tint = KeyboardTheme.make(dark: isDark).text
        switchSideButton.tintColor = tint
        expandButton.tintColor = tint
        let top = keyboardView.frame.minY
        let x = mode == "right" ? 0 : view.bounds.width - gap
        oneHandedStrip.frame = CGRect(x: x, y: top + 20, width: gap, height: max(0, view.bounds.height - top - 40))
    }

    // MARK: Contacts search / translation

    private func updateSearch() {
        let arabic = language == .arabic
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        switch panel {
        case .contacts:
            searchPanel.setQuery(query, placeholder: arabic ? "اكتب اسم…" : "Search contacts…")
            guard ContactsSearcher.isAuthorized else {
                searchPanel.show(message: arabic
                    ? "افتح تطبيق ضاد ← الإعدادات ← اسمح بالوصول لجهات الاتصال. ولازم Allow Full Access يكون مفعّل."
                    : "Open the Daad app → Settings → allow Contacts access. Allow Full Access must be on.")
                return
            }
            guard !trimmed.isEmpty else {
                searchPanel.show(message: arabic ? "اكتب اسم وهتظهر الأرقام والإيميلات" : "Type a name to see numbers and emails")
                return
            }
            let q = trimmed
            ContactsSearcher.search(q) { [weak self] rows in
                guard let self, self.panel == .contacts,
                      self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                if rows.isEmpty {
                    self.searchPanel.show(message: arabic ? "مفيش نتايج" : "No results")
                } else {
                    self.searchPanel.show(rows: rows)
                }
            }
        case .translate:
            searchPanel.setQuery(query, placeholder: arabic ? "اكتب النص اللي عايز تترجمه…" : "Type text to translate…")
            translateWork?.cancel()
            guard !trimmed.isEmpty else {
                searchPanel.show(message: arabic ? "عربي ← English  ·  English ← عربي" : "Arabic ↔ English")
                return
            }
            let q = trimmed
            let work = DispatchWorkItem { [weak self] in
                Translator.translate(q) { text, failure in
                    guard let self, self.panel == .translate,
                          self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                    if let text {
                        self.searchPanel.show(result: text)
                        return
                    }
                    switch failure {
                    case .unsupportedSystem:
                        self.searchPanel.show(message: arabic ? "الترجمة محتاجة iOS 26 أو أحدث" : "Translation needs iOS 26 or later")
                    case .notInstalled:
                        self.searchPanel.show(message: arabic
                            ? "نزّل لغات الترجمة من تطبيق ضاد ← الإعدادات ← تنزيل لغات الترجمة"
                            : "Download the languages in the Daad app → Settings")
                    case .failed(let reason):
                        self.searchPanel.show(message: (arabic ? "الترجمة ماشتغلتش: " : "Translation failed: ") + reason)
                    case nil:
                        break
                    }
                }
            }
            translateWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        default:
            break
        }
    }

    /// Keys typed while searching go into the search text, not the app. Returns true if handled.
    private func handleSearchKey(_ action: KeyAction) -> Bool {
        switch action {
        case .character(let text):
            query += text
        case .space:
            query += " "
        case .returnKey:
            if panel == .translate { translateWork?.perform() }
            return true
        default:
            return false
        }
        if shift == .on { shift = .off }
        reload()
        updateSearch()
        return true
    }

    private func configureClipboardPanel() {
        clipboardPanel.configure(theme: .make(dark: isDark), items: clipboard.items, pinned: clipboard.pinned,
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
            dark: isDark,
            look: KeyLook.current,
            arabicLayout: settings.arabicLayout)
        if force || context != currentContext {
            currentContext = context
            let layout = Layouts.build(context)
            rowCount = layout.rows.count
            let theme = KeyboardTheme.make(dark: context.dark)
            keyboardView.configure(rows: layout.rows, maxUnits: layout.maxUnits, theme: theme, look: context.look)
            suggestionBar.apply(theme: theme)
            updateHeight()
        }
        keyboardView.glideEnabled = mode == .letters && settings.bool(.glideTyping) && !isSearching
        lexicon.blockOffensive = settings.bool(.blockOffensive)
        suggestionBar.setLanguage(language)
        updateSuggestions()
    }

    private func updateHeight() {
        let screen = UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let chosen = CGFloat(min(max(settings.keyHeight, 40), 64))
        let rowHeight: CGFloat = landscape ? chosen * 40 / 52 : chosen
        let top = isSearching ? searchHeight : barHeight
        let height = top + CGFloat(rowCount) * rowHeight + 6
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

    /// Everything typed since the last space (shortcuts like "@@" are not letters).
    private var currentToken: String {
        guard let before = proxy.documentContextBeforeInput else { return "" }
        var token = ""
        for ch in before.reversed() {
            guard !ch.isWhitespace else { break }
            token.insert(ch, at: token.startIndex)
        }
        return token
    }

    /// The word before the one being typed (used to learn which word usually follows which).
    private func previousWord(skipping current: String) -> String? {
        guard var before = proxy.documentContextBeforeInput else { return nil }
        if !current.isEmpty, before.hasSuffix(current) { before.removeLast(current.count) }
        while let last = before.last, last.isWhitespace { before.removeLast() }
        var word = ""
        for ch in before.reversed() {
            guard ch.isLetter || ch == "'" else { break }
            word.insert(ch, at: word.startIndex)
        }
        return word.isEmpty ? nil : word
    }

    private func expansion(for token: String) -> String? {
        guard !token.isEmpty else { return nil }
        if let exact = textShortcuts[token] { return exact }
        return textShortcuts.first { $0.key.lowercased() == token.lowercased() }?.value
    }

    private func updateSuggestions() {
        guard panel == .keys else { return }
        let word = currentWord
        if let glided = lastGlideWord, glided != word {
            lastGlideWord = nil
            glideAlternatives = []
        }
        guard settings.bool(.suggestions) else {
            suggestionBar.showTools()
            return
        }
        // A shortcut being typed shows what it will turn into.
        let token = currentToken
        if let text = expansion(for: token) {
            suggestionBar.show([Suggestion(title: text, value: text, primary: true),
                                Suggestion(title: "\"\(token)\"", value: token, primary: false)])
            return
        }
        if word.isEmpty {
            // After a space: words the user usually types next.
            if (proxy.documentContextBeforeInput ?? "").last == " ",
               let previous = previousWord(skipping: ""),
               case let next = lexicon.nextWords(after: previous, limit: 3), !next.isEmpty {
                suggestionBar.show(arrange(next.map { Suggestion(title: $0, value: $0, primary: false) }))
            } else {
                suggestionBar.showTools()
            }
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
        let ranked = lexicon.rank(word, language: lang, limit: 3)
        let known = ranked.contains { $0.kind == .exact }
        let fix = settings.bool(.autocorrect) ? lexicon.autocorrection(for: word, language: lang) : nil

        var items: [Suggestion] = []
        if known {
            items = ranked.map { Suggestion(title: $0.word, value: $0.word, primary: false) }
        } else {
            // Unknown word: keep what was typed on the side, best guesses in the middle.
            let guesses = ranked.prefix(2).map { Suggestion(title: $0.word, value: $0.word, primary: $0.word == fix) }
            items = guesses.isEmpty ? [] : [guesses[0]]
            items.append(Suggestion(title: "\"\(word)\"", value: word, primary: false))
            if guesses.count > 1 { items.append(guesses[1]) }
        }
        if items.isEmpty { items = [Suggestion(title: "\"\(word)\"", value: word, primary: false)] }
        // Emoji for the word (e.g. حب → ❤️) takes the right-hand slot.
        if settings.bool(.emojiSuggestions),
           let emoji = WordExtras.emoji[Lexicon.normalize(word)]
            ?? ranked.first.flatMap({ WordExtras.emoji[Lexicon.normalize($0.word)] }) {
            items = Array(items.prefix(2)) + [Suggestion(title: emoji, value: emojiMarker + emoji, primary: false)]
        }
        suggestionBar.show(arrange(items))
    }

    /// Puts the most likely item in the middle slot, like Gboard.
    private func arrange(_ items: [Suggestion]) -> [Suggestion] {
        guard items.count == 3 else { return items }
        return [items[1], items[0], items[2]]
    }

    private let emojiMarker = "\u{1}"

    private func applySuggestion(_ value: String) {
        if value.hasPrefix(emojiMarker) {
            // Emoji goes after the word, which stays as typed.
            let emoji = String(value.dropFirst(emojiMarker.count))
            let word = currentWord
            if !word.isEmpty { lexicon.learn(word, after: previousWord(skipping: word)) }
            proxy.insertText(" " + emoji + " ")
            addRecent(emoji)
            feedback(for: .character(emoji))
            reload()
            return
        }
        let word = expansion(for: currentToken) != nil ? currentToken : currentWord
        let previous = previousWord(skipping: word)
        for _ in 0..<word.count { proxy.deleteBackward() }
        proxy.insertText(value + " ")
        if !value.contains(" ") { lexicon.learn(value, after: previous) }
        lastCorrection = nil
        lastGlideWord = nil
        glideAlternatives = []
        feedback(for: .character(value))
        if shift == .on { shift = .off }
        updateAutoShift()
        reload()
    }

    /// Before a space or new line: expand a shortcut, fix the word (autocorrect), and learn it.
    private func commitCurrentWord() {
        lastCorrection = nil
        let token = currentToken
        if let text = expansion(for: token) {
            for _ in 0..<token.count { proxy.deleteBackward() }
            proxy.insertText(text)
            return
        }
        let word = currentWord
        guard !word.isEmpty else { return }
        let previous = previousWord(skipping: word)
        let lang = Lexicon.language(of: word)
        if settings.bool(.autocorrect), lastGlideWord != word,
           let fix = lexicon.autocorrection(for: word, language: lang) {
            for _ in 0..<word.count { proxy.deleteBackward() }
            proxy.insertText(fix)
            lastCorrection = (word, fix)
            lexicon.learn(fix, after: previous)
        } else {
            lexicon.learn(word, after: previous)
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
        keepNumbersInOrder(before: text)
        proxy.insertText(text)
        lastCorrection = nil
        if shift == .on { shift = .off }
        updateAutoShift()
        reload()
    }

    /// Typing "2 4" in right-to-left text shows "4 2". When a digit follows "digit + space", an invisible
    /// left-to-right mark goes before the space so the numbers stay in order. Nothing changes while typing "2 ".
    private func keepNumbersInOrder(before text: String) {
        guard let first = text.first, first.isASCII, first.isNumber else { return }
        let before = Array(proxy.documentContextBeforeInput ?? "")
        guard before.count >= 2, before[before.count - 1] == " ",
              before[before.count - 2].isASCII, before[before.count - 2].isNumber else { return }
        proxy.deleteBackward()
        proxy.insertText("\u{200E} ")
    }

    private func commitWordBeforePunctuation() {
        let word = currentWord
        if !word.isEmpty { lexicon.learn(word, after: previousWord(skipping: word)) }
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

    /// Deletes one visible character, together with any invisible direction marks around it.
    private func deleteOneCharacter() {
        let mark: Character = "\u{200E}"
        while proxy.documentContextBeforeInput?.last == mark { proxy.deleteBackward() }
        proxy.deleteBackward()
        while proxy.documentContextBeforeInput?.last == mark { proxy.deleteBackward() }
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
        if isSearching && handleSearchKey(action) { return }
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
        case .emoji:
            showPanel(.emoji)
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
        if isSearching { _ = handleSearchKey(.character(text)); return }
        insert(text)
    }

    func keyboardViewDeleteBackward(_ view: KeyboardView, word: Bool) {
        if isSearching {
            if !query.isEmpty { query.removeLast() }
            updateSearch()
            return
        }
        // Backspace right after an autocorrect brings back what was typed.
        if !word, let c = lastCorrection, (proxy.documentContextBeforeInput ?? "").hasSuffix(c.replacement + " ") {
            for _ in 0..<(c.replacement.count + 1) { proxy.deleteBackward() }
            proxy.insertText(c.original)
            lastCorrection = nil
            reload()
            return
        }
        lastCorrection = nil
        if word { deleteWord() } else { deleteOneCharacter() }
        updateAutoShift()
        reload()
    }

    func keyboardViewSwitchLanguage(_ view: KeyboardView) {
        language = language.toggled
        settings.language = language
        primaryLanguage = language == .arabic ? "ar" : "en-US"
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

    /// Up/down by lines. Uses line breaks in the text; a long wrapped paragraph moves about one line's worth.
    func keyboardView(_ view: KeyboardView, moveCursorLines lines: Int) {
        let estimatedLine = 32
        for _ in 0..<abs(lines) {
            let before = Array(proxy.documentContextBeforeInput ?? "")
            let after = Array(proxy.documentContextAfterInput ?? "")
            let column = before.count - ((before.lastIndex(of: "\n") ?? -1) + 1)
            if lines < 0 {
                // Up: same column on the previous line.
                guard let lineStart = before.lastIndex(of: "\n") else {
                    proxy.adjustTextPosition(byCharacterOffset: -min(estimatedLine, before.count))
                    continue
                }
                let previousStart = (before[..<lineStart].lastIndex(of: "\n") ?? -1) + 1
                let previousLength = lineStart - previousStart
                let target = previousStart + min(column, previousLength)
                proxy.adjustTextPosition(byCharacterOffset: target - before.count)
            } else {
                // Down: same column on the next line.
                guard let lineEnd = after.firstIndex(of: "\n") else {
                    proxy.adjustTextPosition(byCharacterOffset: min(estimatedLine, after.count))
                    continue
                }
                let rest = after[(lineEnd + 1)...]
                let nextLength = rest.firstIndex(of: "\n").map { $0 - (lineEnd + 1) } ?? rest.count
                proxy.adjustTextPosition(byCharacterOffset: lineEnd + 1 + min(column, nextLength))
            }
        }
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
