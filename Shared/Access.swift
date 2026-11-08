import Foundation
import StoreKit

/// In-app purchase product IDs (both Non-Consumable in App Store Connect).
enum DaadProduct {
    /// Free (price 0) item that starts the 7-day trial. Apple asks one-time-purchase apps to use this.
    static let trial = "com.daad.keyboard.trial7"
    /// One-time purchase that unlocks Daad for good.
    static let lifetime = "com.daad.keyboard.pro"
    static let all = [trial, lifetime]
}

/// What we know about the user's purchases.
struct AccessState: Equatable {
    var purchased = false
    var trialStart: Date?

    /// Combines two sources: bought in either counts, and the earliest trial start wins.
    func merged(with other: AccessState) -> AccessState {
        let starts = [trialStart, other.trialStart].compactMap { $0 }
        return AccessState(purchased: purchased || other.purchased, trialStart: starts.min())
    }
}

enum AccessStatus: Equatable {
    case notStarted
    case trial(daysLeft: Int)
    case expired
    case purchased

    var unlocked: Bool {
        switch self {
        case .purchased, .trial: return true
        case .notStarted, .expired: return false
        }
    }
}

enum Access {
    static let trialDays = 7
    static let trialLength: TimeInterval = TimeInterval(trialDays) * 24 * 3600

    static func status(_ state: AccessState, now: Date = Date()) -> AccessStatus {
        if state.purchased { return .purchased }
        guard let start = state.trialStart else { return .notStarted }
        let left = start.addingTimeInterval(trialLength).timeIntervalSince(now)
        guard left > 0 else { return .expired }
        return .trial(daysLeft: Int((left / 86_400).rounded(.up)))
    }

    // MARK: Stored copy (App Group for the app ↔ keyboard, plus the keyboard's own cache)

    private static let purchasedKey = "accessPurchased"
    private static let trialStartKey = "accessTrialStart"

    static func load(from defaults: UserDefaults) -> AccessState {
        let seconds = defaults.double(forKey: trialStartKey)
        return AccessState(purchased: defaults.bool(forKey: purchasedKey),
                           trialStart: seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil)
    }

    static func save(_ state: AccessState, to defaults: UserDefaults) {
        defaults.set(state.purchased, forKey: purchasedKey)
        defaults.set(state.trialStart?.timeIntervalSince1970 ?? 0, forKey: trialStartKey)
    }

    // MARK: StoreKit (works in the app and, read-only, in the keyboard)

    /// Reads verified purchases from StoreKit. Returns nil when StoreKit gave nothing usable.
    static func fromStoreKit() async -> AccessState? {
        var state = AccessState()
        var found = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            found = true
            switch transaction.productID {
            case DaadProduct.lifetime:
                state.purchased = true
            case DaadProduct.trial:
                state.trialStart = min(state.trialStart ?? transaction.purchaseDate, transaction.purchaseDate)
            default:
                break
            }
        }
        return found ? state : nil
    }
}
