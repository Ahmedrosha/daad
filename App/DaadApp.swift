import SwiftUI

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
