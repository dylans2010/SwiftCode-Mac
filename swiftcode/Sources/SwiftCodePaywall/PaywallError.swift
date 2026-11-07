import Foundation

public enum PaywallError: Error, LocalizedError, Equatable, Sendable {
    case storeKitUnavailable
    case productsUnavailable
    case productFetchFailed(message: String)
    case purchaseFailed(message: String)
    case transactionUnverified
    case restoreFailed(message: String)
    case subscriptionsUnavailable

    public var errorDescription: String? {
        switch self {
        case .storeKitUnavailable:
            return "StoreKit is not available on this platform. Purchases and entitlements need macOS or iOS with the StoreKit framework."
        case .productsUnavailable:
            return "No SwiftCode Pro products were returned from the App Store. Check that the products exist in App Store Connect and that the app is signed with the team that owns them."
        case let .productFetchFailed(message):
            return "Could not load SwiftCode Pro products from the App Store: \(message)"
        case let .purchaseFailed(message):
            return "The purchase could not be completed: \(message)"
        case .transactionUnverified:
            return "The App Store returned a transaction that failed verification. It was not counted as a SwiftCode Pro entitlement."
        case let .restoreFailed(message):
            return "Could not restore purchases: \(message)"
        case .subscriptionsUnavailable:
            return "Manage Subscriptions cannot be opened on this platform."
        }
    }
}

public enum PaywallPurchaseOutcome: Equatable, Sendable {
    case purchased
    case userCancelled
    case pending
}
