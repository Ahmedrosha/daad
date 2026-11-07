import SwiftUI
import Contacts
#if canImport(Translation)
import Translation
#endif

@main
struct DaadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("الرئيسية", systemImage: "house") }
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape") }
        }
    }
}

struct HomeView: View {
    @State private var testText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("تفعيل الكيبورد") {
                    StepRow(number: 1, text: "افتح الإعدادات من الزرار تحت")
                    StepRow(number: 2, text: "ادخل على Keyboards")
                    StepRow(number: 3, text: "فعّل ضاد")
                    StepRow(number: 4, text: "فعّل Allow Full Access عشان الصوت والاهتزاز")
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("افتح الإعدادات", systemImage: "gear")
                    }
                }
                Section("اضغط على 🌐 واختار ضاد") {
                    TextField("جرّب الكتابة هنا…", text: $testText, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("حركات المسافة") {
                    Text("ضغطة عادية: مسافة")
                    Text("ضغطة مطوّلة وسيب: تبديل عربي / English")
                    Text("ضغطة مطوّلة واسحب يمين وشمال: تحريك المؤشر")
                    Text("ضغطتين ورا بعض: نقطة")
                }
            }
            .navigationTitle("ضاد")
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

struct SettingsView: View {
    @AppStorage(DaadSetting.numberRow.rawValue, store: SharedSettings.store) private var numberRow = true
    @AppStorage(DaadSetting.arabicDigits.rawValue, store: SharedSettings.store) private var arabicDigits = true
    @AppStorage(DaadSetting.autoCapitalize.rawValue, store: SharedSettings.store) private var autoCapitalize = true
    @AppStorage(DaadSetting.quickPeriod.rawValue, store: SharedSettings.store) private var quickPeriod = true
    @AppStorage(DaadSetting.keySound.rawValue, store: SharedSettings.store) private var keySound = true
    @AppStorage(DaadSetting.haptics.rawValue, store: SharedSettings.store) private var haptics = true
    @AppStorage(DaadSetting.keyPopups.rawValue, store: SharedSettings.store) private var keyPopups = true
    @AppStorage(DaadSetting.rtlMark.rawValue, store: SharedSettings.store) private var rtlMark = false
    @AppStorage(DaadSetting.suggestions.rawValue, store: SharedSettings.store) private var suggestions = true
    @AppStorage(DaadSetting.autocorrect.rawValue, store: SharedSettings.store) private var autocorrect = false
    @AppStorage(DaadSetting.glideTyping.rawValue, store: SharedSettings.store) private var glideTyping = true
    @State private var confirmClear = false
    @State private var cleared = false

    var body: some View {
        NavigationStack {
            Form {
                Section("الأرقام") {
                    Toggle("صف الأرقام", isOn: $numberRow)
                    Toggle("أرقام عربية ١٢٣ في الكيبورد العربي", isOn: $arabicDigits)
                }
                Section("الكتابة") {
                    Toggle("اقتراح الكلمات", isOn: $suggestions)
                    Toggle("التصحيح التلقائي", isOn: $autocorrect)
                    Toggle("الكتابة بالسحب", isOn: $glideTyping)
                    Toggle("نقطة بضغطتين على المسافة", isOn: $quickPeriod)
                    Toggle("حرف كابيتال أول الجملة (English)", isOn: $autoCapitalize)
                    Toggle("علامة اتجاه عربي أول النص", isOn: $rtlMark)
                }
                Section {
                    Toggle("صوت الضغط", isOn: $keySound)
                    Toggle("اهتزاز الضغط", isOn: $haptics)
                    Toggle("معاينة الحرف", isOn: $keyPopups)
                } header: {
                    Text("الإحساس")
                } footer: {
                    Text("الاهتزاز، والحافظة، ووصول الإعدادات دي للكيبورد محتاجين تفعيل Allow Full Access.")
                }
                Section {
                    NavigationLink("الاختصارات") { ShortcutsView() }
                    NavigationLink("المحفوظات في الحافظة") { PinnedTextsView() }
                } header: {
                    Text("النصوص")
                } footer: {
                    Text("مثلاً اكتب @@ ودوس مسافة يتكتب إيميلك.")
                }
                Section {
                    ContactsAccessRow()
                    if #available(iOS 18.0, *) {
                        TranslationDownloadRow()
                    } else {
                        Text("الترجمة محتاجة iOS 26 أو أحدث").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("الأدوات")
                } footer: {
                    Text("الترجمة بتشتغل على التليفون من غير نت بعد تنزيل اللغات، وجوه الكيبورد محتاجة iOS 26.")
                }
                Section {
                    Button(cleared ? "اتمسح ✓" : "مسح الكلمات اللي اتعلمها الكيبورد", role: .destructive) {
                        confirmClear = true
                    }
                    .disabled(cleared)
                } header: {
                    Text("القاموس")
                } footer: {
                    Text("قوائم الكلمات: FrequencyWords – Hermit Dave (CC BY-SA 4.0)")
                }
            }
            .confirmationDialog("تمسح كل الكلمات اللي اتعلمها الكيبورد؟", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("مسح", role: .destructive) {
                    SharedSettings.shared.requestClearLearned()
                    cleared = true
                }
            }
            .navigationTitle("الإعدادات")
        }
    }
}

private struct ContactsAccessRow: View {
    @State private var status = CNContactStore.authorizationStatus(for: .contacts)

    var body: some View {
        if status == .authorized {
            Label("الوصول لجهات الاتصال مفعّل", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button {
                CNContactStore().requestAccess(for: .contacts) { _, _ in
                    DispatchQueue.main.async { status = CNContactStore.authorizationStatus(for: .contacts) }
                }
            } label: {
                Label("السماح بالوصول لجهات الاتصال", systemImage: "person.crop.circle")
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TranslationDownloadRow: View {
    @State private var configuration: TranslationSession.Configuration?
    @State private var done = false

    var body: some View {
        Button {
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "ar"),
                target: Locale.Language(identifier: "en"))
        } label: {
            Label(done ? "لغات الترجمة جاهزة ✓" : "تنزيل لغات الترجمة (عربي / English)",
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

private struct ShortcutItem: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

private struct ShortcutsView: View {
    @State private var items: [ShortcutItem] = []
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        Form {
            Section("اختصار جديد") {
                TextField("الاختصار (مثلاً @@)", text: $newKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("النص (مثلاً إيميلك)", text: $newValue, axis: .vertical)
                    .lineLimit(1...5)
                Button("إضافة", action: add)
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
                Text("الاختصارات")
            } footer: {
                Text("اكتب الاختصار في أي مكان ودوس مسافة يتبدّل بالنص. اختصارات الـ iPhone نفسه (Text Replacement) بتشتغل كمان. محتاج Allow Full Access.")
            }
        }
        .navigationTitle("الاختصارات")
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

private struct PinnedTextsView: View {
    @State private var items: [String] = []
    @State private var newText = ""

    var body: some View {
        Form {
            Section("نص جديد") {
                TextField("مثلاً عنوانك أو رقم حسابك", text: $newText, axis: .vertical)
                    .lineLimit(1...6)
                Button("حفظ", action: add)
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                ForEach(items, id: \.self) { Text($0).lineLimit(3) }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
            } header: {
                Text("المحفوظات")
            } footer: {
                Text("بتظهر على طول فوق في الحافظة جوه الكيبورد. وتقدر كمان تثبّت أي حاجة نسختها بسحبة عليها في الكيبورد.")
            }
        }
        .navigationTitle("المحفوظات")
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
