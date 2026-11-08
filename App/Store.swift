import SwiftUI
import StoreKit

/// Loads products, handles the trial / lifetime purchase and shares the result with the keyboard.
@MainActor
final class DaadStore: ObservableObject {
    @Published private(set) var state = AccessState()
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?
    private let shared = SharedSettings.store ?? .standard

    init() {
        state = Access.load(from: shared)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await loadProducts(); await refresh() }
    }

    deinit { updates?.cancel() }

    var status: AccessStatus { Access.status(state) }
    var lifetimePrice: String? { products[DaadProduct.lifetime]?.displayPrice }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: DaadProduct.all)
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            products = [:]
        }
    }

    /// Re-reads purchases from StoreKit and writes them where the keyboard can see them.
    func refresh() async {
        if let fromStore = await Access.fromStoreKit() {
            state = fromStore
        }
        Access.save(state, to: shared)
    }

    func startTrial(arabic: Bool) async { await buy(DaadProduct.trial, arabic: arabic) }
    func buyLifetime(arabic: Bool) async { await buy(DaadProduct.lifetime, arabic: arabic) }

    func restore(arabic: Bool) async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            if !status.unlocked {
                message = arabic ? "مفيش مشتريات سابقة على الحساب ده" : "No previous purchases on this account"
            }
        } catch {
            message = arabic ? "الاستعادة ما نجحتش، جرّب تاني" : "Restore failed, try again"
        }
    }

    private func buy(_ id: String, arabic: Bool) async {
        if products[id] == nil { await loadProducts() }
        guard let product = products[id] else {
            message = arabic ? "المتجر مش متاح دلوقتي، جرّب بعد شوية" : "The store isn't available right now, try later"
            return
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let transaction) = result { await transaction.finish() }
                await refresh()
            case .pending:
                message = arabic ? "الشراء مستني موافقة" : "Purchase is waiting for approval"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = arabic ? "الشراء ما نجحش، جرّب تاني" : "Purchase failed, try again"
        }
    }
}

/// The purchase card at the top of the Home screen.
struct AccessSection: View {
    @Environment(\.arabic) private var ar
    @ObservedObject var store: DaadStore

    var body: some View {
        Section {
            switch store.status {
            case .purchased:
                Label(ar ? "ضاد مفتوح مدى الحياة. شكرًا!" : "Daad is unlocked for life. Thank you!",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .trial(let days):
                Label(ar ? "التجربة المجانية: فاضل \(days) \(days == 1 ? "يوم" : "أيام")"
                         : "Free trial: \(days) day\(days == 1 ? "" : "s") left",
                      systemImage: "clock")
                buyButton
            case .notStarted:
                Text(ar ? "جرّب ضاد ببلاش 7 أيام، وبعدها اشتريه مرة واحدة."
                        : "Try Daad free for 7 days, then buy it once.")
                Button {
                    Task { await store.startTrial(arabic: ar) }
                } label: {
                    Label(ar ? "ابدأ التجربة المجانية (7 أيام)" : "Start free trial (7 days)", systemImage: "gift")
                }
                buyButton
            case .expired:
                Label(ar ? "التجربة المجانية خلصت، والكيبورد مقفول لحد الشراء."
                         : "Your free trial has ended. The keyboard is locked until you buy.",
                      systemImage: "lock.fill")
                    .foregroundStyle(.orange)
                buyButton
            }
            if store.status != .purchased {
                Button(ar ? "استعادة المشتريات" : "Restore purchases") {
                    Task { await store.restore(arabic: ar) }
                }
                .font(.footnote)
            }
        } header: {
            Text(ar ? "ضاد مدى الحياة" : "Daad lifetime")
        } footer: {
            if store.status != .purchased {
                Text(ar ? "شراء مرة واحدة، من غير اشتراك. بيفضل معاك لو غيّرت الموبايل بنفس حساب أبل."
                        : "One-time purchase, no subscription. It stays with your Apple ID on any iPhone.")
            }
        }
        .disabled(store.busy)
        .alert(store.message ?? "", isPresented: Binding(get: { store.message != nil },
                                                         set: { if !$0 { store.message = nil } })) {
            Button(ar ? "تمام" : "OK", role: .cancel) {}
        }
    }

    private var buyButton: some View {
        Button {
            Task { await store.buyLifetime(arabic: ar) }
        } label: {
            HStack {
                Label(ar ? "اشترِ ضاد مدى الحياة" : "Buy Daad for life", systemImage: "cart")
                    .fontWeight(.semibold)
                Spacer()
                if let price = store.lifetimePrice {
                    Text(price).fontWeight(.semibold)   // its own view, so Arabic/English order can't flip it
                }
            }
        }
    }
}
