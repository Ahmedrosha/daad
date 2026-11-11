import SwiftUI
import PhotosUI
import Contacts
#if canImport(Translation)
import Translation
#endif

// MARK: - App language (Arabic / English)

private struct ArabicKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True when the app's own screens are shown in Arabic.
    var arabic: Bool {
        get { self[ArabicKey.self] }
        set { self[ArabicKey.self] = newValue }
    }
}

private let defaultAppLanguage = (Locale.preferredLanguages.first ?? "ar").hasPrefix("ar") ? "ar" : "en"

@main
struct DaadApp: App {
    @AppStorage("appLanguage") private var appLanguage = defaultAppLanguage
    @StateObject private var store = DaadStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DaadApp.applyDirection(UserDefaults.standard.string(forKey: "appLanguage") ?? defaultAppLanguage)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .id(appLanguage)   // rebuild screens so UIKit picks up the new direction
                .environment(\.arabic, appLanguage == "ar")
                .environment(\.layoutDirection, appLanguage == "ar" ? .rightToLeft : .leftToRight)
                .onChange(of: appLanguage) { DaadApp.applyDirection($0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { Task { await store.refresh() } }
                }
        }
    }

    /// The app's base language is Arabic, so UIKit lays screens out right-to-left. When English is chosen,
    /// UIKit must switch too; otherwise pushed screens (like Text shortcuts) come out mirrored.
    static func applyDirection(_ language: String) {
        let attribute: UISemanticContentAttribute = language == "ar" ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attribute
        UINavigationBar.appearance().semanticContentAttribute = attribute
    }
}

struct ContentView: View {
    @Environment(\.arabic) private var ar
    @ObservedObject var store: DaadStore

    var body: some View {
        TabView {
            HomeView(store: store)
                .tabItem { Label(ar ? "الرئيسية" : "Home", systemImage: "house") }
            SettingsView()
                .tabItem { Label(ar ? "الإعدادات" : "Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @Environment(\.arabic) private var ar
    @Environment(\.openURL) private var openURL
    @ObservedObject var store: DaadStore
    @State private var testText = ""

    var body: some View {
        NavigationStack {
            List {
                AccessSection(store: store)
                Section(ar ? "تفعيل الكيبورد" : "Turn on the keyboard") {
                    StepRow(number: 1, text: ar ? "افتح الإعدادات من الزرار تحت" : "Open Settings with the button below")
                    StepRow(number: 2, text: ar ? "ادخل على Keyboards" : "Tap Keyboards")
                    StepRow(number: 3, text: ar ? "فعّل ضاد" : "Turn on Daad")
                    StepRow(number: 4, text: ar ? "فعّل Allow Full Access" : "Turn on Allow Full Access")
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label(ar ? "افتح الإعدادات" : "Open Settings", systemImage: "gear")
                    }
                }
                Section(ar ? "اضغط على 🌐 واختار ضاد" : "Tap 🌐 and choose Daad") {
                    TextField(ar ? "جرّب الكتابة هنا…" : "Try typing here…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section(ar ? "حركات المسافة" : "Space bar gestures") {
                    Text(ar ? "ضغطة عادية: مسافة" : "Tap: space")
                    Text(ar ? "ضغطة مطوّلة وسيب: تبديل عربي / English" : "Hold and release: switch Arabic / English")
                    Text(ar ? "ضغطة مطوّلة واسحب: تحريك المؤشر" : "Hold and slide: move the cursor")
                    Text(ar ? "ضغطتين ورا بعض: نقطة" : "Double tap: period")
                }
                Section(ar ? "الشريط اللي فوق الحروف" : "Bar above the keys") {
                    Label(ar ? "تنزيل الكيبورد وتبديل اللغة" : "Hide keyboard and switch language", systemImage: "keyboard.chevron.compact.down")
                    Label(ar ? "إيموجي، حاسبة، حافظة" : "Emoji, calculator, clipboard", systemImage: "face.smiling")
                    Label(ar ? "▦ كل الأدوات: ترجمة، جهات اتصال، يد واحدة، الحجم والخط" : "▦ All tools: translate, contacts, one-handed, size & font", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle(ar ? "ضاد" : "Daad")
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.arabic) private var ar
    @AppStorage("appLanguage") private var appLanguage = defaultAppLanguage

    // Typing
    @AppStorage(DaadSetting.suggestions.rawValue, store: SharedSettings.store) private var suggestions = true
    @AppStorage(DaadSetting.autocorrect.rawValue, store: SharedSettings.store) private var autocorrect = false
    @AppStorage(DaadSetting.glideTyping.rawValue, store: SharedSettings.store) private var glideTyping = true
    @AppStorage(DaadSetting.emojiSuggestions.rawValue, store: SharedSettings.store) private var emojiSuggestions = true
    @AppStorage(DaadSetting.blockOffensive.rawValue, store: SharedSettings.store) private var blockOffensive = true
    @AppStorage(DaadSetting.quickPeriod.rawValue, store: SharedSettings.store) private var quickPeriod = true
    @AppStorage(DaadSetting.autoCapitalize.rawValue, store: SharedSettings.store) private var autoCapitalize = true
    // Layout
    @AppStorage(DaadSetting.numberRow.rawValue, store: SharedSettings.store) private var numberRow = true
    @AppStorage(DaadSetting.arrowRow.rawValue, store: SharedSettings.store) private var arrowRow = false
    @AppStorage(DaadSetting.franco.rawValue, store: SharedSettings.store) private var franco = true
    @AppStorage(DaadSetting.splitLandscape.rawValue, store: SharedSettings.store) private var splitLandscape = true
    @AppStorage("keyboardTheme", store: SharedSettings.store) private var keyboardTheme = "system"
    @AppStorage("keySoundStyle", store: SharedSettings.store) private var keySoundStyle = "classic"
    @AppStorage("hapticStyle", store: SharedSettings.store) private var hapticStyle = "light"
    @State private var photoItem: PhotosPickerItem?
    @State private var photoSaved = false
    @AppStorage(DaadSetting.swipeUpSymbols.rawValue, store: SharedSettings.store) private var swipeUpSymbols = true
    @State private var enabledModes = SharedSettings.shared.enabledModes
    @AppStorage(DaadSetting.autoLanguage.rawValue, store: SharedSettings.store) private var autoLanguage = true
    @AppStorage(DaadSetting.harakatOnHold.rawValue, store: SharedSettings.store) private var harakatOnHold = true
    @AppStorage(DaadSetting.arabicDigits.rawValue, store: SharedSettings.store) private var arabicDigits = true
    @AppStorage("oneHandedMode", store: SharedSettings.store) private var oneHandedMode = "off"
    @AppStorage(DaadSetting.rtlMark.rawValue, store: SharedSettings.store) private var rtlMark = false
    @AppStorage("arabicLayout", store: SharedSettings.store) private var arabicLayout = "iphone"
    // Size & font
    @AppStorage("letterFontScale", store: SharedSettings.store) private var letterScale = 1.0
    @AppStorage("numberFontScale", store: SharedSettings.store) private var numberScale = 1.0
    @AppStorage("keyHeight", store: SharedSettings.store) private var keyHeight = 52.0
    @AppStorage("keyboardWidthScale", store: SharedSettings.store) private var widthScale = 1.0
    @AppStorage("keyFont", store: SharedSettings.store) private var keyFont = "system"
    // Feedback
    @AppStorage(DaadSetting.keySound.rawValue, store: SharedSettings.store) private var keySound = true
    @AppStorage(DaadSetting.haptics.rawValue, store: SharedSettings.store) private var haptics = true
    @AppStorage(DaadSetting.keyPopups.rawValue, store: SharedSettings.store) private var keyPopups = true

    @State private var confirmClear = false
    @State private var cleared = false

    private func t(_ arabic: String, _ english: String) -> String { ar ? arabic : english }

    private func modeTitle(_ mode: InputMode) -> String {
        switch mode {
        case .arabic: return t("عربي", "Arabic")
        case .english: return t("إنجليزي", "English")
        case .dual: return t("الاتنين مع بعض (ع+En)", "Both together (ع+En)")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(t("لغة التطبيق", "App language"), selection: $appLanguage) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                } footer: {
                    Text(t("لغة الشاشات دي بس. لغة الكتابة بتتغير من الكيبورد.", "Only these screens. The typing language is switched on the keyboard."))
                }

                Section(t("الكتابة", "Typing")) {
                    Toggle(t("اقتراح الكلمات", "Word suggestions"), isOn: $suggestions)
                    Toggle(t("التصحيح التلقائي", "Autocorrect"), isOn: $autocorrect)
                    Toggle(t("الكتابة بالسحب", "Glide typing"), isOn: $glideTyping)
                    Toggle(t("اقتراح إيموجي", "Emoji suggestions"), isOn: $emojiSuggestions)
                    Toggle(t("فرانكو ← عربي (3amel ← عامل)", "Franco → Arabic (3amel → عامل)"), isOn: $franco)
                    Toggle(t("منع الكلمات البذيئة من الاقتراحات", "Block offensive words"), isOn: $blockOffensive)
                    Toggle(t("نقطة بضغطتين على المسافة", "Double-space period"), isOn: $quickPeriod)
                    Toggle(t("حرف كابيتال أول الجملة (English)", "Auto-capitalize (English)"), isOn: $autoCapitalize)
                }

                Section {
                    ForEach(InputMode.allCases, id: \.self) { mode in
                        Toggle(isOn: Binding(
                            get: { enabledModes.contains(mode) },
                            set: { on in
                                var list = enabledModes.filter { $0 != mode }
                                if on { list.append(mode) }
                                guard !list.isEmpty else { return }   // keep at least one
                                enabledModes = InputMode.allCases.filter(list.contains)
                                SharedSettings.shared.enabledModes = enabledModes
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modeTitle(mode))
                                if mode == .dual {
                                    Text(t("حروف عربي بالضغط، وإنجليزي بالسحب لتحت على نفس الزرار. الكتابة بالسحب مقفولة فيه.",
                                           "Tap for Arabic, flick down on the same key for English. Swipe typing is off in it."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(t("الكيبوردات اللي بتقلب بينهم", "Keyboards you switch between"))
                } footer: {
                    Text(t("اقلب بزرار اللغة فوق، أو اضغط مطوّل على المسافة، أو اسحب سحبة سريعة على المسافة: يمين للّي بعده وشمال للّي قبله.",
                           "Switch with the language button, a long press on the space bar, or a quick flick on it: right for the next, left for the previous."))
                }

                Section {
                    NavigationLink(t("زراير البار اللي فوق الحروف", "Buttons in the bar above the keys")) { BarItemsView() }
                } footer: {
                    Text(t("رتّبهم واختار اللي يظهر. لو كتير، البار بيتسحب يمين وشمال.",
                           "Order them and pick which show. If there are many, the bar scrolls sideways."))
                }

                Section(t("شكل الكيبورد", "Layout")) {
                    Picker(t("ترتيب الحروف العربي", "Arabic letter layout"), selection: $arabicLayout) {
                        Text(t("زي الآيفون", "Like iPhone")).tag("iphone")
                        Text(t("زي Gboard", "Like Gboard")).tag("gboard")
                    }
                    Toggle(t("صف الأرقام", "Number row"), isOn: $numberRow)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(t("اللغة حسب الكلمة اللي قبل المؤشر", "Pick the language from the word before the cursor"), isOn: $autoLanguage)
                        Text(t("لما الكيبورد يتفتح أو تحرك المؤشر. وتقدر تقلب اللغة بسحبة سريعة يمين أو شمال على المسافة.",
                               "When the keyboard opens or you move the cursor. You can also switch with a quick flick left or right on the space bar."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle(t("صف أسهم تحريك المؤشر", "Cursor arrow row"), isOn: $arrowRow)
                    Toggle(t("كيبورد مقسوم في الوضع العرضي", "Split keyboard in landscape"), isOn: $splitLandscape)
                    Toggle(t("رموز وأرقام بالسحب لفوق على الحروف", "Flick up on letters for numbers and symbols"), isOn: $swipeUpSymbols)
                    Toggle(t("التشكيل بالضغط المطوّل على الحرف", "Harakat on long press"), isOn: $harakatOnHold)
                    Toggle(t("أرقام عربية ١٢٣ في الكيبورد العربي", "Arabic digits ١٢٣ on the Arabic keyboard"), isOn: $arabicDigits)
                    Picker(t("وضع اليد الواحدة", "One-handed mode"), selection: $oneHandedMode) {
                        Text(t("مقفول", "Off")).tag("off")
                        Text(t("يمين", "Right")).tag("right")
                        Text(t("شمال", "Left")).tag("left")
                    }
                    Toggle(t("علامة اتجاه عربي أول النص", "Arabic direction mark at start"), isOn: $rtlMark)
                }

                Section {
                    LabeledSlider(title: t("حجم الحروف", "Letter size"), value: $letterScale, range: 0.7...1.4)
                    LabeledSlider(title: t("حجم الأرقام", "Number size"), value: $numberScale, range: 0.7...1.4)
                    LabeledSlider(title: t("ارتفاع الكيبورد", "Keyboard height"), value: $keyHeight, range: 40...64)
                    LabeledSlider(title: t("عرض الكيبورد", "Keyboard width"), value: $widthScale, range: 0.7...1.0)
                    Picker(t("شكل الحروف", "Key font"), selection: $keyFont) {
                        ForEach(KeyFont.allCases, id: \.rawValue) { font in
                            Text("ض  \(font.title)").font(Font(font.font(size: 17) as CTFont)).tag(font.rawValue)
                        }
                    }
                    Button(t("إعادة ضبط الحجم والخط", "Reset size & font")) {
                        letterScale = 1; numberScale = 1; keyHeight = 52; widthScale = 1; keyFont = "system"
                    }
                } header: {
                    Text(t("الحجم والخط", "Size & font"))
                }

                Section {
                    Picker(t("الثيم", "Theme"), selection: $keyboardTheme) {
                        Text(t("زي التليفون", "Match phone")).tag("system")
                        Text(t("فاتح", "Light")).tag("light")
                        Text(t("غامق", "Dark")).tag("dark")
                        Text(t("أزرق", "Ocean")).tag("ocean")
                        Text(t("أخضر", "Forest")).tag("forest")
                        Text(t("بنفسجي", "Purple")).tag("purple")
                        Text(t("رملي", "Sand")).tag("sand")
                        Text(t("صورة من عندك", "Your photo")).tag("photo")
                    }
                    if keyboardTheme == "photo" {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoSaved ? t("الصورة اتحفظت ✓", "Photo saved ✓") : t("اختار صورة الخلفية", "Choose background photo"),
                                  systemImage: "photo")
                        }
                        .onChange(of: photoItem) { item in saveBackground(item) }
                    }
                } header: {
                    Text(t("الألوان", "Colors"))
                } footer: {
                    Text(t("صورة الخلفية محتاجة Allow Full Access عشان الكيبورد يشوفها.", "The photo background needs Allow Full Access."))
                }

                Section(t("الإحساس", "Feel")) {
                    Toggle(t("صوت الضغط", "Key sound"), isOn: $keySound)
                    Picker(t("نوع الصوت", "Sound"), selection: $keySoundStyle) {
                        Text(t("كلاسيك", "Classic")).tag("classic")
                        Text(t("رنين", "Tink")).tag("tink")
                        Text(t("طقة", "Tock")).tag("tock")
                        Text(t("ناعم", "Soft")).tag("soft")
                    }
                    Toggle(t("اهتزاز الضغط", "Haptics"), isOn: $haptics)
                    Picker(t("قوة الاهتزاز", "Haptic strength"), selection: $hapticStyle) {
                        Text(t("خفيف", "Light")).tag("light")
                        Text(t("ناعم", "Soft")).tag("soft")
                        Text(t("متوسط", "Medium")).tag("medium")
                        Text(t("قوي", "Heavy")).tag("heavy")
                        Text(t("حاد", "Rigid")).tag("rigid")
                    }
                    Toggle(t("معاينة الحرف", "Key pop-ups"), isOn: $keyPopups)
                }

                Section {
                    NavigationLink(t("الاختصارات", "Text shortcuts")) { ShortcutsView() }
                    NavigationLink(t("المحفوظات في الحافظة", "Pinned clipboard texts")) { PinnedTextsView() }
                } header: {
                    Text(t("النصوص", "Texts"))
                } footer: {
                    Text(t("مثلاً اكتب @@ ودوس مسافة يتكتب إيميلك.", "For example type @@ then space to write your email."))
                }

                Section {
                    ContactsAccessRow()
                    if #available(iOS 18.0, *) {
                        TranslationDownloadRow()
                    } else {
                        Text(t("الترجمة محتاجة iOS 26 أو أحدث", "Translation needs iOS 26 or later")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(t("الأدوات", "Tools"))
                } footer: {
                    Text(t("الترجمة بتشتغل على التليفون من غير نت بعد تنزيل اللغات، وجوه الكيبورد محتاجة iOS 26.",
                           "Translation runs on the phone without internet after downloading the languages; inside the keyboard it needs iOS 26."))
                }

                Section {
                    Button(cleared ? t("اتمسح ✓", "Cleared ✓") : t("مسح الكلمات اللي اتعلمها الكيبورد", "Clear learned words"), role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(cleared)
                } header: {
                    Text(t("القاموس", "Dictionary"))
                } footer: {
                    Text(t("قوائم الكلمات: FrequencyWords – Hermit Dave (CC BY-SA 4.0). اقتراح الكلمة الجاية: جمل Tatoeba (CC BY 2.0 FR).",
                           "Word lists: FrequencyWords – Hermit Dave (CC BY-SA 4.0). Next-word data: Tatoeba sentences (CC BY 2.0 FR)."))
                }

                Section {
                    Text(t("معظم الإعدادات دي بتوصل للكيبورد لما يكون Allow Full Access مفعّل.",
                           "Most of these settings reach the keyboard only when Allow Full Access is on."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent(t("النسخة", "Version"), value: appVersion)
                }
            }
            .navigationTitle(t("الإعدادات", "Settings"))
            .confirmationDialog(t("تمسح كل الكلمات اللي اتعلمها الكيبورد؟", "Clear all learned words?"),
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button(t("مسح", "Clear"), role: .destructive) {
                    SharedSettings.shared.requestClearLearned()
                    cleared = true
                }
            }
        }
    }

    /// Saves the chosen photo, made smaller, where the keyboard can read it.
    private func saveBackground(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data), let url = SharedSettings.backgroundImageURL else { return }
            let width: CGFloat = 900
            let scale = min(1, width / image.size.width)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = resized.jpegData(compressionQuality: 0.8) {
                try? jpeg.write(to: url, options: .atomic)
                await MainActor.run { photoSaved = true }
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Tools rows

private struct ContactsAccessRow: View {
    @Environment(\.arabic) private var ar
    @State private var status = CNContactStore.authorizationStatus(for: .contacts)

    var body: some View {
        if status == .authorized {
            Label(ar ? "الوصول لجهات الاتصال مفعّل" : "Contacts access is on", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button {
                CNContactStore().requestAccess(for: .contacts) { _, _ in
                    DispatchQueue.main.async { status = CNContactStore.authorizationStatus(for: .contacts) }
                }
            } label: {
                Label(ar ? "السماح بالوصول لجهات الاتصال" : "Allow contacts access", systemImage: "person.crop.circle")
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TranslationDownloadRow: View {
    @Environment(\.arabic) private var ar
    @State private var configuration: TranslationSession.Configuration?
    @State private var done = false

    var body: some View {
        Button {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ar"),
                target: Locale.Language(identifier: "en"))
        } label: {
            Label(done ? (ar ? "لغات الترجمة جاهزة ✓" : "Translation languages ready ✓")
                       : (ar ? "تنزيل لغات الترجمة (عربي / English)" : "Download translation languages (Arabic / English)"),
                  systemImage: "arrow.down.circle")
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                done = true
            } catch {
                done = false
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutItem: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

private struct ShortcutsView: View {
    @Environment(\.arabic) private var ar
    @State private var items: [ShortcutItem] = []
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        Form {
            Section(ar ? "اختصار جديد" : "New shortcut") {
                TextField(ar ? "الاختصار (مثلاً @@)" : "Shortcut (e.g. @@)", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(ar ? "النص (مثلاً إيميلك)" : "Text (e.g. your email)", text: $newValue, axis: .vertical)
                    .lineLimit(1...5)
                Button(ar ? "إضافة" : "Add", action: add)
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty || newValue.isEmpty)
            }
            Section {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.key).font(.headline)
                        Text(item.value).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text(ar ? "الاختصارات" : "Shortcuts")
            } footer: {
                Text(ar ? "اكتب الاختصار في أي مكان ودوس مسافة يتبدّل بالنص. اختصارات الـ iPhone نفسه (Text Replacement) بتشتغل كمان."
                        : "Type a shortcut anywhere and press space to replace it. The iPhone's own Text Replacements work too.")
            }
        }
        .navigationTitle(ar ? "الاختصارات" : "Text shortcuts")
        .onAppear(perform: load)
    }

    private func load() {
        items = SharedSettings.shared.shortcuts
            .sorted { $0.key < $1.key }
            .map { ShortcutItem(key: $0.key, value: $0.value) }
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" "), !newValue.isEmpty else { return }
        var map = SharedSettings.shared.shortcuts
        map[key] = newValue
        SharedSettings.shared.shortcuts = map
        newKey = ""
        newValue = ""
        load()
    }

    private func delete(_ offsets: IndexSet) {
        var map = SharedSettings.shared.shortcuts
        for i in offsets { map[items[i].key] = nil }
        SharedSettings.shared.shortcuts = map
        load()
    }
}

// MARK: - Pinned texts

private struct PinnedTextsView: View {
    @Environment(\.arabic) private var ar
    @State private var items: [String] = []
    @State private var newText = ""

    var body: some View {
        Form {
            Section(ar ? "نص جديد" : "New text") {
                TextField(ar ? "مثلاً عنوانك أو رقم حسابك" : "e.g. your address or account number", text: $newText, axis: .vertical)
                    .lineLimit(1...6)
                Button(ar ? "حفظ" : "Save", action: add)
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                ForEach(items, id: \.self) { Text($0).lineLimit(3) }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
            } header: {
                Text(ar ? "المحفوظات" : "Pinned")
            } footer: {
                Text(ar ? "بتظهر على طول فوق في الحافظة جوه الكيبورد. وتقدر كمان تثبّت أي حاجة نسختها بسحبة عليها في الكيبورد."
                        : "Always shown at the top of the keyboard clipboard. You can also pin anything you copied by swiping it in the keyboard.")
            }
        }
        .navigationTitle(ar ? "المحفوظات" : "Pinned texts")
        .toolbar { EditButton() }
        .onAppear { items = SharedSettings.shared.pinnedTexts }
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !items.contains(text) else { return }
        items.insert(text, at: 0)
        SharedSettings.shared.pinnedTexts = items
        newText = ""
    }

    private func delete(_ offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        SharedSettings.shared.pinnedTexts = items
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        SharedSettings.shared.pinnedTexts = items
    }
}

/// Order and show/hide the bar buttons. Hide and language always stay on the left.
private struct BarItemsView: View {
    @Environment(\.arabic) private var ar
    @State private var order = SharedSettings.shared.barOrder
    @State private var hidden = SharedSettings.shared.barHidden

    private func t(_ arabic: String, _ english: String) -> String { ar ? arabic : english }

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { item in
                    Toggle(isOn: Binding(get: { !hidden.contains(item) },
                                         set: { on in
                                             if on { hidden.remove(item) } else { hidden.insert(item) }
                                             SharedSettings.shared.barHidden = hidden
                                         })) {
                        HStack(spacing: 12) {
                            icon(item).frame(width: 28)
                            Text(ar ? item.arabicTitle : item.englishTitle)
                        }
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    SharedSettings.shared.barOrder = order
                }
            } footer: {
                Text(t("اسحب من العلامة ☰ عشان ترتّب. الأول في القايمة هو أول واحد من الشمال في البار. زرار الإخفاء وزرار اللغة ثابتين.",
                       "Drag the ☰ handle to reorder. The first in the list is the leftmost in the bar. Hide and language stay put."))
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(t("زراير البار", "Bar buttons"))
    }

    @ViewBuilder private func icon(_ item: BarItem) -> some View {
        if item == .gif {
            Text("GIF").font(.system(size: 12, weight: .heavy))
        } else if item == .calculator {
            Image(uiImage: DaadIcons.calculator(size: 22)).renderingMode(.template)
        } else {
            Image(systemName: item.symbol ?? "questionmark")
        }
    }
}
