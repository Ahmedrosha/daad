import UIKit
import AudioToolbox

final class KeyboardViewController: UIInputViewController {
    private let keyboardView = KeyboardView()
    private var heightConstraint: NSLayoutConstraint?
    private let settings = SharedSettings.shared

    private var language: DaadLanguage = .arabic
    private var mode: KeyboardMode = .letters
    private var shift: ShiftState = .off
    private var lastShiftTap: Date?
    private var lastSpaceTap: Date?
    private var currentContext: LayoutContext?
    private var rowCount = 4

    private lazy var tapHaptic = UIImpactFeedbackGenerator(style: .light)
    private lazy var tickHaptic = UISelectionFeedbackGenerator()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        language = settings.language
        keyboardView.delegate = self
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        mode = .letters
        updateAutoShift()
        reload(force: true)   // picks up changes made in the app's Settings screen
        if settings.bool(.haptics) && hasFullAccess { tapHaptic.prepare() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        allowImmediateTouches()
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
        updateAutoShift()
        reload()
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
        guard force || context != currentContext else { return }
        currentContext = context
        let layout = Layouts.build(context)
        rowCount = layout.rows.count
        keyboardView.configure(rows: layout.rows, maxUnits: layout.maxUnits, theme: .make(dark: context.dark))
        updateHeight()
    }

    private func updateHeight() {
        let screen = UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let rowHeight: CGFloat = landscape ? 40 : 54
        let height = CGFloat(rowCount) * rowHeight + 6
        if let c = heightConstraint {
            c.constant = height
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: height)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: Text helpers

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    private func insert(_ text: String) {
        if language == .arabic, settings.bool(.rtlMark),
           (proxy.documentContextBeforeInput ?? "").isEmpty,
           (proxy.documentContextAfterInput ?? "").isEmpty {
            proxy.insertText("\u{200F}")
        }
        proxy.insertText(text)
        if shift == .on { shift = .off }
        updateAutoShift()
        reload()
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
        } else {
            proxy.insertText(" ")
            lastSpaceTap = now
        }
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
            proxy.insertText("\n")
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
        case .backspace:
            break
        }
    }

    func keyboardView(_ view: KeyboardView, insertAlternate text: String) {
        insert(text)
    }

    func keyboardViewDeleteBackward(_ view: KeyboardView, word: Bool) {
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
        if settings.bool(.keySound) {
            if hasFullAccess {
                let sound: SystemSoundID
                switch action {
                case .backspace: sound = 1155
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

    func keyboardViewTickFeedback(_ view: KeyboardView) {
        if settings.bool(.haptics) && hasFullAccess { tickHaptic.selectionChanged() }
    }
}
