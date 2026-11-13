import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    private let suggestionBar = SuggestionBarView()
    private let lockView = LockView()
    private var access = AccessState()
    private let keyboardView = KeyboardView()
    private let emojiPanel = EmojiPanelView()
    private let clipboardPanel = ClipboardPanelView()
    private let toolsPanel = ToolsPanelView()
    private let calculatorPanel = CalculatorPanelView()
    private let settingsPanel = SettingsPanelView()
    private let searchPanel = SearchPanelView()
    private let lookPanel = LookPanelView()
    private let editPanel = EditPanelView()
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

    private enum Panel { case keys, emoji, clipboard, tools, calculator, settings, look, editing, contacts, translate, emojiSearch, gif }
    private var panel: Panel = .keys
    /// Contacts search and translation are typed with the keyboard's own keys.
    private var isSearching: Bool { [.contacts, .translate, .emojiSearch, .gif].contains(panel) }
    private var gifResults: [GifResult] = []
    private var gifWork: DispatchWorkItem?
    private var query = ""
    private var translateWork: DispatchWorkItem?
    private let searchHeight: CGFloat = 190
    private let lookHeight: CGFloat = 230
    /// Panels that keep the real keys visible underneath.
    private var keysVisible: Bool { panel == .keys || isSearching || panel == .look }
    private var topHeight: CGFloat { isSearching ? searchHeight : (panel == .look ? lookHeight : barHeight) }

    private var language: DaadLanguage = .arabic
    /// Arabic, English, or both (Arabic keys with English letters by flicking down).
    private var inputMode: InputMode = .arabic
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
    /// Fixed while a space-bar swipe is in progress, so passing over an English word inside Arabic
    /// text (or the opposite) doesn't flip the direction mid-swipe.
    private var lockedCursorDirection: Bool?
    private var systemShortcuts: [String: String] = [:]

    private lazy var tapHaptic = UIImpactFeedbackGenerator(style: hapticStyle)
    private let backgroundImageView = UIImageView()

    private var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch settings.hapticStyle {
        case "medium": return .medium
        case "heavy": return .heavy
        case "soft": return .soft
        case "rigid": return .rigid
        default: return .light
        }
    }

    private var currentTheme: KeyboardTheme {
        KeyboardTheme.make(style: settings.keyboardTheme, dark: isDark)
    }

    /// Shows the photo background when the "photo" theme is chosen (needs Full Access to read it).
    private func updateBackgroundImage() {
        guard settings.keyboardTheme == "photo", hasFullAccess,
              let url = SharedSettings.backgroundImageURL,
              let image = UIImage(contentsOfFile: url.path) else {
            backgroundImageView.image = nil
            backgroundImageView.isHidden = true
            return
        }
        backgroundImageView.image = image
        backgroundImageView.isHidden = false
    }
    private lazy var tickHaptic = UISelectionFeedbackGenerator()

    private var store: UserDefaults {
        hasFullAccess ? (SharedSettings.store ?? .standard) : .standard
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        inputMode = settings.inputMode
        if !settings.enabledModes.contains(inputMode) { inputMode = settings.enabledModes[0] }
        language = inputMode.language
        // Tells the app which language is being typed, so it lays the text out the right way.
        primaryLanguage = language == .arabic ? "ar" : "en-US"
        lexicon.configure(store: store)
        clipboard.configure(store: store)

        keyboardView.delegate = self
        keyboardLeading = keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        keyboardTrailing = keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let overlays: [UIView] = [emojiPanel, clipboardPanel, toolsPanel, calculatorPanel, settingsPanel, editPanel]
        for v in [suggestionBar, keyboardView, searchPanel, lookPanel] + overlays {
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
            // Size & font sits above the real keyboard, so changes show live.
            lookPanel.leadingAnchor.constraint(equalTo: suggestionBar.leadingAnchor),
            lookPanel.trailingAnchor.constraint(equalTo: suggestionBar.trailingAnchor),
            lookPanel.topAnchor.constraint(equalTo: suggestionBar.topAnchor),
            lookPanel.bottomAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardLeading,
            keyboardTrailing,
            keyboardView.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let barConstraint = suggestionBar.heightAnchor.constraint(equalToConstant: barHeight)
        barConstraint.isActive = true
        barHeightConstraint = barConstraint
        searchPanel.isHidden = true
        lookPanel.isHidden = true
        for p in overlays {
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                p.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                p.topAnchor.constraint(equalTo: view.topAnchor),
                p.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            p.isHidden = true
        }
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(backgroundImageView, at: 0)
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
        setUpLockView()
    }

    // MARK: Trial / purchase lock

    private func setUpLockView() {
        lockView.translatesAutoresizingMaskIntoConstraints = false
        lockView.isHidden = true
        view.addSubview(lockView)
        NSLayoutConstraint.activate([
            lockView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            lockView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            lockView.topAnchor.constraint(equalTo: view.topAnchor),
            lockView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        lockView.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        lockView.hideButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
    }

    /// Reads the purchase state the app shared, the keyboard's own cache, and StoreKit itself
    /// (StoreKit works even without Full Access), then locks or unlocks the keys.
    private func loadAccess() {
        var state = Access.load(from: .standard)
        if hasFullAccess, let group = SharedSettings.store {
            state = state.merged(with: Access.load(from: group))
        }
        access = state
        Access.save(state, to: .standard)
        applyAccess()
        Task { [weak self] in
            guard let fromStore = await Access.fromStoreKit() else { return }
            await MainActor.run {
                guard let self else { return }
                self.access = self.access.merged(with: fromStore)
                Access.save(self.access, to: .standard)
                self.applyAccess()
            }
        }
    }

    private func applyAccess() {
        let status = Access.status(access)
        lockView.isHidden = status.unlocked
        guard !status.unlocked else { return }
        lockView.configure(status: status, arabic: language == .arabic, showGlobe: needsInputModeSwitchKey)
        view.bringSubviewToFront(lockView)
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
        suggestionBar.setItems(settings.barItems)
        autoPickLanguage(refresh: false)
        updateAutoShift()
        reload(force: true)   // picks up changes made in the app's Settings screen
        tapHaptic = UIImpactFeedbackGenerator(style: hapticStyle)
        if settings.bool(.haptics) && hasFullAccess { tapHaptic.prepare() }
        updateBackgroundImage()
        loadAccess()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowImmediateTouches()
        // Some apps (WhatsApp) read the language before their text box is ready, so the cursor can open
        // on the wrong side. Say it again once the keyboard is up, and once more a moment later.
        announceLanguage()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.announceLanguage() }
    }

    /// Re-sends the keyboard language the same way switching languages does (to the other and back),
    /// so an empty text box puts the cursor on the right for Arabic and on the left for English.
    private func announceLanguage() {
        let empty = (proxy.documentContextBeforeInput ?? "").isEmpty && (proxy.documentContextAfterInput ?? "").isEmpty
        guard empty else { return }   // with text in the box, the text itself decides the side
        let code = language == .arabic ? "ar" : "en-US"
        primaryLanguage = code == "ar" ? "en-US" : "ar"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.primaryLanguage = self.language == .arabic ? "ar" : "en-US"
        }
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
        // While the space bar moves the cursor, don't rebuild the keys (e.g. auto-Shift at a sentence start):
        // rebuilding cancels the touch and ends the cursor swipe. Catch up when the finger lifts.
        guard lockedCursorDirection == nil else { return }
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
        suggestionBar.onPaste = { [weak self] in
            guard let self else { return }
            let arabic = self.language == .arabic
            guard self.hasFullAccess else {   // iOS blocks the clipboard without Full Access
                self.suggestionBar.flash(arabic ? "اللصق محتاج Allow Full Access" : "Paste needs Allow Full Access")
                return
            }
            let board = UIPasteboard.general
            if let text = board.string, !text.isEmpty {
                self.recordingUndo { self.textDocumentProxy.insertText(text) }
                self.feedback(for: .character(text))
                self.reload()
            } else if board.hasImages || board.contains(pasteboardTypes: ["com.compuserve.gif"]) {
                // Keyboards can only type text; a GIF or picture has to be pasted by the app itself.
                self.suggestionBar.flash(arabic ? "اضغط مطوّل في خانة الكتابة واختار لصق (Paste)"
                                                : "Long-press the text box and choose Paste")
            } else {
                self.suggestionBar.flash(arabic ? "مفيش حاجة منسوخة" : "Nothing copied")
            }
        }
        suggestionBar.onGif = { [weak self] in self?.showPanel(.gif) }
        suggestionBar.onCopyAll = { [weak self] in
            self?.copyAllText { message in self?.suggestionBar.flash(message) }
        }
        suggestionBar.onDeleteAll = { [weak self] in
            self?.deleteAllText { message in self?.suggestionBar.flash(message) }
        }
        suggestionBar.onArrows = { [weak self] in
            guard let self else { return }
            self.settings.set(!self.settings.bool(.arrowRow), for: .arrowRow)
            self.reload(force: true)
        }
        suggestionBar.onLanguage = { [weak self] in
            guard let self else { return }
            self.keyboardViewSwitchLanguage(self.keyboardView, forward: true)
        }
        lookPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        editPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        editPanel.onAction = { [weak self] action in self?.performEdit(action) }
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
            case .editing: self.showPanel(.editing)
            case .gif: self.showPanel(.gif)
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
            self.recordingUndo { self.textDocumentProxy.insertText(emoji) }
            self.addRecent(emoji)
        }
        emojiPanel.onBackspace = { [weak self] in
            self?.feedback(for: .backspace)
            self?.textDocumentProxy.deleteBackward()
        }
        emojiPanel.onClose = { [weak self] in self?.showPanel(.keys) }
        emojiPanel.onSearch = { [weak self] in self?.showPanel(.emojiSearch) }
        emojiPanel.onGif = { [weak self] in self?.showPanel(.gif) }
        searchPanel.onPickItem = { [weak self] index in self?.pickSearchItem(index) }

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
        let theme = currentTheme
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
        case .editing:
            editPanel.configure(theme: theme, arabic: arabic)
        case .contacts:
            query = ""
            mode = .letters
            searchPanel.configure(theme: theme, title: arabic ? "جهات الاتصال" : "Contacts", insertTitle: nil)
        case .emojiSearch:
            query = ""
            mode = .letters
            searchPanel.configure(theme: theme, title: arabic ? "بحث في الإيموجي" : "Search emoji", insertTitle: nil)
        case .gif:
            query = ""
            mode = .letters
            gifResults = []
            searchPanel.configure(theme: theme, title: "GIF", insertTitle: nil)
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
        editPanel.isHidden = newPanel != .editing
        searchPanel.isHidden = !isSearching
        suggestionBar.isHidden = newPanel != .keys
        keyboardView.isHidden = !keysVisible
        barHeightConstraint?.constant = topHeight
        updateHeight()
        if isSearching { reload(force: true); updateSearch() }
        if newPanel == .look { reload(force: true) }
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
        let active = mode != "off" && keysVisible
        let gap = active ? floor(view.bounds.width * 0.16) : 0
        var leading = mode == "right" ? gap : 0
        var trailing = mode == "left" ? -gap : 0
        if !active && keysVisible {
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
        let tint = currentTheme.text
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
        case .emojiSearch:
            searchPanel.setQuery(query, placeholder: arabic ? "قلب، ضحك، ورد…" : "heart, laugh, flower…")
            let found = trimmed.isEmpty ? recents : WordExtras.searchEmoji(trimmed)
            if found.isEmpty {
                searchPanel.show(message: arabic ? (trimmed.isEmpty ? "اكتب كلمة زي: قلب" : "مفيش نتايج") : (trimmed.isEmpty ? "Type a word like: heart" : "No results"))
            } else {
                searchPanel.show(items: found, images: false)
            }
        case .gif:
            searchPanel.setQuery(query, placeholder: arabic ? "دوّر على GIF…" : "Search GIFs…")
            guard hasFullAccess else {
                searchPanel.show(message: arabic ? "الـ GIF محتاج Allow Full Access عشان النت" : "GIFs need Allow Full Access for internet")
                return
            }
            guard GifSearch.apiKey != nil else {
                searchPanel.show(message: arabic ? "مفتاح GIPHY مش موجود في النسخة دي" : "GIPHY key is missing in this build")
                return
            }
            gifWork?.cancel()
            let q = trimmed
            let work = DispatchWorkItem { [weak self] in
                GifSearch.search(q) { results in
                    guard let self, self.panel == .gif, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                    guard let results else {
                        self.searchPanel.show(message: arabic ? "مفيش نت" : "No internet connection")
                        return
                    }
                    self.gifResults = results
                    self.searchPanel.show(items: results.map { _ in "" }, images: true, footer: "Powered by GIPHY")
                    for (i, r) in results.enumerated() {
                        GifSearch.loadImage(r.preview) { [weak self] image in
                            guard let self, let image, self.panel == .gif, i < self.gifResults.count,
                                  self.gifResults[i].preview == r.preview else { return }
                            self.searchPanel.setImage(image, at: i)
                        }
                    }
                }
            }
            gifWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (q.isEmpty ? 0 : 0.6), execute: work)
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

    private func pickSearchItem(_ index: Int) {
        let arabic = language == .arabic
        switch panel {
        case .emojiSearch:
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            let found = trimmed.isEmpty ? recents : WordExtras.searchEmoji(trimmed)
            guard found.indices.contains(index) else { return }
            recordingUndo { proxy.insertText(found[index]) }
            addRecent(found[index])
            feedback(for: .character(found[index]))
        case .gif:
            guard gifResults.indices.contains(index) else { return }
            searchPanel.setFooter(arabic ? "بيتنسخ…" : "Copying…")
            GifSearch.copy(gifResults[index].full) { [weak self] ok in
                self?.searchPanel.setFooter(ok ? (arabic ? "اتنسخ ✓ اضغط مطوّل في خانة الكتابة واختار لصق" : "Copied ✓ Long-press the text box and choose Paste")
                                               : (arabic ? "ماتنسخش، جرّب تاني" : "Couldn't copy, try again"))
            }
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
        clipboardPanel.configure(theme: currentTheme, items: clipboard.items, pinned: clipboard.pinned,
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
            // On (ع+En), digits follow the language you're typing: English digits while English is big.
            arabicDigits: settings.bool(.arabicDigits) && !(inputMode == .dual && currentDualLook.tapsEnglish),
            needsGlobe: needsInputModeSwitchKey,
            returnLabel: returnLabel,
            dark: isDark,
            look: KeyLook.current,
            arabicLayout: settings.arabicLayout,
            arrowRow: settings.bool(.arrowRow) && !isSearching,
            // The both-languages keyboard has its own switch for the flick-up symbols.
            swipeUpSymbols: settings.bool(.swipeUpSymbols) && (inputMode != .dual || settings.bool(.dualSymbols)),
            dual: inputMode == .dual,
            dualLook: currentDualLook,
            harakatOnHold: settings.bool(.harakatOnHold),
            theme: settings.keyboardTheme)
        if force || context != currentContext {
            currentContext = context
            let layout = Layouts.build(context)
            rowCount = layout.rows.count
            let theme = currentTheme
            keyboardView.configure(rows: layout.rows, maxUnits: layout.maxUnits, theme: theme, look: context.look)
            suggestionBar.apply(theme: theme)
            updateHeight()
        }
        keyboardView.glideEnabled = mode == .letters && settings.bool(.glideTyping) && !isSearching
            // On (ع+En) a down-flick could read as a glide; only the automatic look allows swipe typing,
            // in the language whose letters are big.
            && (inputMode != .dual || settings.dualLook == .automatic)
        keyboardView.splitWhenWide = settings.bool(.splitLandscape)
        lexicon.blockOffensive = settings.bool(.blockOffensive)
        suggestionBar.setInputMode(inputMode)
        suggestionBar.setArrowsOn(settings.bool(.arrowRow))
        updateSuggestions()
    }

    private func updateHeight() {
        let screen = UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let chosen = CGFloat(min(max(settings.keyHeight, 40), 64))
        let rowHeight: CGFloat = landscape ? chosen * 40 / 52 : chosen
        let top = topHeight
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

    // MARK: Undo and text editing

    /// One change made by the keyboard: text removed before the cursor and text added in its place.
    private struct EditRecord {
        var removed: String
        var added: String
    }
    private var undoStack: [EditRecord] = []
    private var isUndoing = false

    /// Runs a change and remembers it, so "Undo" can reverse it. Letters typed in a row undo as one word.
    private func recordingUndo(_ body: () -> Void) {
        guard !isUndoing else { body(); return }
        let old = Array(proxy.documentContextBeforeInput ?? "")
        body()
        let new = Array(proxy.documentContextBeforeInput ?? "")
        var p = 0
        while p < old.count, p < new.count, old[p] == new[p] { p += 1 }
        guard old.count - p <= 300, new.count - p <= 300 else { return }   // the text window moved; skip
        let record = EditRecord(removed: String(old[p...]), added: String(new[p...]))
        guard !(record.removed.isEmpty && record.added.isEmpty) else { return }
        if record.removed.isEmpty, let last = undoStack.last, last.removed.isEmpty,
           !record.added.contains(where: \.isWhitespace), !(last.added.last?.isWhitespace ?? true) {
            undoStack[undoStack.count - 1].added += record.added
        } else {
            undoStack.append(record)
            if undoStack.count > 50 { undoStack.removeFirst() }
        }
    }

    private func undoLastEdit() -> Bool {
        guard let record = undoStack.popLast() else { return false }
        isUndoing = true
        for _ in 0..<record.added.count { proxy.deleteBackward() }
        if !record.removed.isEmpty { proxy.insertText(record.removed) }
        isUndoing = false
        return true
    }

    private func performEdit(_ action: EditAction) {
        let arabic = language == .arabic
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let rtl = textIsRightToLeft
        func wordBack() -> Int {
            var chars = Array(before), n = 0
            while let c = chars.last, !c.isLetter && !c.isNumber { chars.removeLast(); n += 1 }
            while let c = chars.last, c.isLetter || c.isNumber { chars.removeLast(); n += 1 }
            return n
        }
        func wordForward() -> Int {
            var chars = Array(after)[...], n = 0
            while let c = chars.first, !c.isLetter && !c.isNumber { chars.removeFirst(); n += 1 }
            while let c = chars.first, c.isLetter || c.isNumber { chars.removeFirst(); n += 1 }
            return n
        }
        switch action {
        case .left, .right:
            let visualRight = action == .right
            proxy.adjustTextPosition(byCharacterOffset: visualRight == rtl ? -1 : 1)
        case .up: keyboardView(keyboardView, moveCursorLines: -1)
        case .down: keyboardView(keyboardView, moveCursorLines: 1)
        case .wordLeft, .wordRight:
            let backward = (action == .wordRight) == rtl
            proxy.adjustTextPosition(byCharacterOffset: backward ? -wordBack() : wordForward())
        case .lineStart: keyboardView(keyboardView, moveCursorToLineEdge: false)
        case .lineEnd: keyboardView(keyboardView, moveCursorToLineEdge: true)
        case .textStart: proxy.adjustTextPosition(byCharacterOffset: -before.count)
        case .textEnd: proxy.adjustTextPosition(byCharacterOffset: after.count)
        case .deleteWord:
            recordingUndo { deleteWord() }
        case .undo:
            if !undoLastEdit() { editPanel.flash(arabic ? "مفيش حاجة للتراجع" : "Nothing to undo") }
        case .copy, .cut:
            guard hasFullAccess else {
                editPanel.flash(arabic ? "محتاج Allow Full Access" : "Needs Allow Full Access")
                return
            }
            guard let selected = proxy.selectedText, !selected.isEmpty else {
                editPanel.flash(arabic ? "حدد كلام الأول" : "Select some text first")
                return
            }
            UIPasteboard.general.string = selected
            if action == .cut { recordingUndo { proxy.deleteBackward() } }
            editPanel.flash(arabic ? (action == .cut ? "اتقص ✓" : "اتنسخ ✓") : (action == .cut ? "Cut ✓" : "Copied ✓"))
        case .paste:
            guard hasFullAccess, let text = UIPasteboard.general.string, !text.isEmpty else {
                editPanel.flash(arabic ? "مفيش حاجة منسوخة، أو Allow Full Access مقفول" : "Nothing to paste, or Full Access is off")
                return
            }
            recordingUndo { proxy.insertText(text) }
        case .copyAll:
            copyAllText { [weak self] message in self?.editPanel.flash(message) }
        case .deleteAll:
            deleteAllText { [weak self] message in self?.editPanel.flash(message) }
        }
    }

    // MARK: Whole text (a keyboard can't select, so it reads the text by walking the cursor)

    /// Reads the whole text in the box. The keyboard only sees the text near the cursor, so it moves the
    /// cursor to the end, then back to the start chunk by chunk, and finally puts it back where it was.
    /// Calls back with the text and the cursor's place in it.
    private func readAllText(_ done: @escaping (_ text: String, _ cursor: Int) -> Void) {
        var forward = 0, back = 0, collected = ""
        func toEnd(_ step: Int) {
            let after = proxy.documentContextAfterInput ?? ""
            guard !after.isEmpty, step < 80 else { toStart(0); return }
            proxy.adjustTextPosition(byCharacterOffset: after.count)
            forward += after.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { toEnd(step + 1) }
        }
        func toStart(_ step: Int) {
            let before = proxy.documentContextBeforeInput ?? ""
            guard !before.isEmpty, step < 80 else {
                let cursor = back - forward
                proxy.adjustTextPosition(byCharacterOffset: cursor)   // back to where it was
                done(collected, cursor)
                return
            }
            collected = before + collected
            proxy.adjustTextPosition(byCharacterOffset: -before.count)
            back += before.count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { toStart(step + 1) }
        }
        toEnd(0)
    }

    private func copyAllText(_ report: @escaping (String) -> Void) {
        let arabic = language == .arabic
        guard hasFullAccess else { report(arabic ? "محتاج Allow Full Access" : "Needs Allow Full Access"); return }
        readAllText { text, _ in
            guard !text.isEmpty else { report(arabic ? "الخانة فاضية" : "The box is empty"); return }
            UIPasteboard.general.string = text
            report(arabic ? "اتنسخ الكل ✓" : "Copied all ✓")
        }
    }

    private func deleteAllText(_ report: @escaping (String) -> Void) {
        let arabic = language == .arabic
        readAllText { [weak self] text, cursor in
            guard let self else { return }
            guard !text.isEmpty else { report(arabic ? "الخانة فاضية" : "The box is empty"); return }
            self.proxy.adjustTextPosition(byCharacterOffset: text.count - cursor)   // to the end
            for _ in 0..<text.count { self.proxy.deleteBackward() }
            self.undoStack.append(EditRecord(removed: text, added: ""))   // Undo puts it all back
            self.updateAutoShift()
            self.reload()
            report(arabic ? "اتمسح الكل. ترجّعه من تعديل النص ← تراجع" : "Deleted all. Bring it back with Text editing → Undo")
        }
    }

    /// The two words before the one being typed, or nil where a sentence starts.
    private func previousTwoWords(skipping current: String) -> (String?, String?) {
        guard var before = proxy.documentContextBeforeInput else { return (nil, nil) }
        if !current.isEmpty, before.hasSuffix(current) { before.removeLast(current.count) }
        var found: [String] = []
        while found.count < 2 {
            while let last = before.last, last == " " { before.removeLast() }
            guard let last = before.last, last.isLetter || last == "'" else { break }   // punctuation ends the context
            var word = ""
            while let ch = before.last, ch.isLetter || ch == "'" {
                word.insert(ch, at: word.startIndex)
                before.removeLast()
            }
            found.append(word)
        }
        return (found.first, found.count > 1 ? found[1] : nil)
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
        // Franco: "3amel" → عامل. With Franco digits the Arabic takes all slots; otherwise one slot
        // when the word isn't English.
        if settings.bool(.franco), Lexicon.looksLikeFranco(token) {
            let arabic = lexicon.francoCandidates(token, limit: 3)
            if !arabic.isEmpty {
                if Lexicon.hasFrancoDigit(token) {
                    var items = arabic.map { Suggestion(title: $0, value: francoMarker + $0, primary: false) }
                    if items.count < 3 { items.append(Suggestion(title: "\"\(token)\"", value: token, primary: false)) }
                    suggestionBar.show(arrange(items))
                    return
                } else if !lexicon.isKnown(token, language: .english) {
                    let english = lexicon.rank(token, language: .english, limit: 2).map {
                        Suggestion(title: $0.word, value: $0.word, primary: false)
                    }
                    let items = [Suggestion(title: arabic[0], value: francoMarker + arabic[0], primary: false)]
                        + [Suggestion(title: "\"\(token)\"", value: token, primary: false)] + english.prefix(1)
                    suggestionBar.show(arrange(items))
                    return
                }
            }
        }
        if word.isEmpty {
            // After a space: the words most likely to come next.
            let before = proxy.documentContextBeforeInput ?? ""
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            guard before.last == " ", !trimmed.isEmpty else {
                suggestionBar.showTools()     // empty field: keep the tools handy
                return
            }
            let sentenceStart = trimmed.last.map { ".!?؟\n".contains($0) } ?? true
            let (p1, p2) = sentenceStart ? (nil, nil) : previousTwoWords(skipping: "")
            let lang = p1.map(Lexicon.language(of:)) ?? language
            var next = lexicon.predictions(previous: p1, beforePrevious: p2, language: lang, limit: 3)
            if lang == .english && (shift != .off) {
                next = next.map { shift == .locked ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
            }
            if next.isEmpty {
                suggestionBar.showTools()
            } else {
                suggestionBar.show(arrange(next.map { Suggestion(title: $0, value: $0, primary: false) }))
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
        let (p1, p2) = previousTwoWords(skipping: word)
        let ranked = lexicon.rank(word, language: lang, limit: 3, previous: p1, beforePrevious: p2)
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
    private let francoMarker = "\u{2}"

    private func applySuggestion(_ value: String) {
        recordingUndo {
            if value.hasPrefix(francoMarker) {
                // Replace the Franco word (letters and digits) with the Arabic one.
                let arabic = String(value.dropFirst(francoMarker.count))
                let token = currentToken
                for _ in 0..<token.count { proxy.deleteBackward() }
                proxy.insertText(arabic + " ")
                lexicon.learn(arabic, after: nil)
                feedback(for: .character(arabic))
                reload()
                return
            }
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
        // The both-languages keyboard has a Shift for its English letters too.
        guard language == .english || inputMode == .dual, mode == .letters, settings.bool(.autoCapitalize) else { return false }
        return capitalizationContext()
    }

    /// Whether the text field expects a capital letter at the cursor (start of a sentence, a word, …).
    private func capitalizationContext() -> Bool {
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
                case .character, .space:
                    switch settings.keySoundStyle {
                    case "tink": sound = 1103
                    case "tock": sound = 1105
                    case "soft": sound = 1123
                    default: sound = 1104
                    }
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
    var nextLanguageName: String { inputMode.step(true, enabled: settings.enabledModes).displayName }
    var popupsEnabled: Bool { settings.bool(.keyPopups) }

    func keyboardView(_ view: KeyboardView, didTap action: KeyAction) {
        recordingUndo {
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
            case .arrow(let direction):
                switch direction {
                case .left: proxy.adjustTextPosition(byCharacterOffset: textIsRightToLeft ? 1 : -1)
                case .right: proxy.adjustTextPosition(byCharacterOffset: textIsRightToLeft ? -1 : 1)
                case .up: keyboardView(view, moveCursorLines: -1)
                case .down: keyboardView(view, moveCursorLines: 1)
                }
                lastCorrection = nil
                updateSuggestions()
            case .forwardDelete:
                guard let after = proxy.documentContextAfterInput, let next = after.first else { return }
                proxy.adjustTextPosition(byCharacterOffset: next.utf16.count)
                proxy.deleteBackward()
                reload()
            case .backspace:
                break
            }
        }
    }

    /// Dual keyboard: the letter from flicking down (already capital when Shift is on).
    func keyboardView(_ view: KeyboardView, insertFlickDown text: String) {
        keyboardView(view, insertAlternate: text)
    }

    func keyboardView(_ view: KeyboardView, insertAlternate text: String) {
        recordingUndo {
            if isSearching { _ = handleSearchKey(.character(text)); return }
            insert(text)
        }
    }

    func keyboardViewDeleteBackward(_ view: KeyboardView, word: Bool) {
        recordingUndo {
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
    }

    func keyboardViewSwitchLanguage(_ view: KeyboardView, forward: Bool) {
        setInputMode(inputMode.step(forward, enabled: settings.enabledModes))
    }

    /// How the letters sit on (ع+En) right now (the automatic look follows the last letter typed).
    private var currentDualLook: DualLook {
        settings.dualLook.resolved(lastLetter: Self.languageBefore(proxy.documentContextBeforeInput ?? ""))
    }

    private func setInputMode(_ new: InputMode, refresh: Bool = true) {
        inputMode = new
        language = new.language
        settings.inputMode = new
        primaryLanguage = language == .arabic ? "ar" : "en-US"
        mode = .letters
        guard refresh else { return }
        updateAutoShift()
        reload()
    }

    /// The language of the last word before the cursor (nil when there is no letter to go by).
    static func languageBefore(_ text: String) -> DaadLanguage? {
        for ch in text.reversed().prefix(80) where ch.isLetter {
            return TextHelpers.isArabic(ch) ? .arabic : .english
        }
        return nil
    }

    /// Picks the keyboard language from the word before the cursor: when the keyboard opens and after
    /// moving the cursor, never while typing, so it doesn't flip mid-sentence.
    private func autoPickLanguage(refresh: Bool) {
        // "Both" already types either language, so it stays put.
        guard settings.bool(.autoLanguage), mode == .letters, !isSearching, inputMode != .dual,
              let found = Self.languageBefore(proxy.documentContextBeforeInput ?? ""), found != language else { return }
        let target: InputMode = found == .arabic ? .arabic : .english
        guard settings.enabledModes.contains(target) else { return }
        setInputMode(target, refresh: refresh)
    }

    func keyboardViewCursorGesture(_ view: KeyboardView, began: Bool) {
        lockedCursorDirection = began ? paragraphIsRightToLeft : nil
        if !began {
            autoPickLanguage(refresh: false)
            updateAutoShift()
            reload()   // also refreshes the suggestions
        }
    }

    /// Direction of the current line, from its first real letter (how iOS lays the line out).
    private var paragraphIsRightToLeft: Bool {
        let before = proxy.documentContextBeforeInput ?? ""
        let line = before.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let rest = after.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if let ch = (line + rest).first(where: { $0.isLetter }) { return TextHelpers.isArabic(ch) }
        return language == .arabic
    }

    /// Direction of the text around the cursor, from the nearest real letter (spaces and digits don't count).
    private var textIsRightToLeft: Bool {
        if let locked = lockedCursorDirection { return locked }
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        if let ch = before.reversed().first(where: { $0.isLetter }) ?? after.first(where: { $0.isLetter }) {
            return TextHelpers.isArabic(ch)
        }
        return language == .arabic
    }

    func keyboardView(_ view: KeyboardView, moveCursorBy steps: Int) {
        // Finger to the right moves the cursor visually right; in Arabic text that is backwards.
        proxy.adjustTextPosition(byCharacterOffset: textIsRightToLeft ? -steps : steps)
    }

    func keyboardView(_ view: KeyboardView, moveCursorToLineEdge right: Bool) {
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        // Visual right is the start of the line in Arabic and the end in English.
        let toStart = right == textIsRightToLeft
        if toStart {
            let count = before.reversed().prefix(while: { $0 != "\n" }).count
            if count > 0 { proxy.adjustTextPosition(byCharacterOffset: -count) }
        } else {
            let count = after.prefix(while: { $0 != "\n" }).count
            if count > 0 { proxy.adjustTextPosition(byCharacterOffset: count) }
        }
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
        recordingUndo {
            // On (ع+En), swipe typing writes the language of the big letters.
            let glideLanguage: DaadLanguage = inputMode == .dual ? (currentDualLook.tapsEnglish ? .english : .arabic) : language
            var results = GlideDecoder.decode(path: path, keyCenters: keyCenters, keyWidth: keyWidth,
                                              language: glideLanguage, lexicon: lexicon)
            guard !results.isEmpty else { return }
            if glideLanguage == .english && shift != .off {
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
    }
