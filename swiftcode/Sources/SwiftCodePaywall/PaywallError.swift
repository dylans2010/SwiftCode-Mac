import Foundation

/// Typed paywall errors. Messages name the cause and, where there is
/// one, the fix; they never include a receipt, token, transaction ID,
/// or any other purchase credential.
public enum PaywallError: Error, LocalizedError, Equatable, Sendable {
    /// StoreKit is not available on this platform (e.g. Linux). No
    /// purchase, restore, or entitlement check can run here; nothing
    /// is faked in its place.
    case storeKitUnavailable
    /// The live product fetch returned no products for the catalog.
    /// The products may not exist in App Store Connect yet, or the
    /// app may not be signed with the App Store Connect team that
    /// owns them.
    case productsUnavailable
    /// The live product fetch failed.
    case productFetchFailed(message: String)
    /// A purchase attempt failed after the user confirmed it.
    case purchaseFailed(message: String)
    /// The App Store returned a transaction whose signature or
    /// bundle check failed verification. It is not counted as an
    /// entitlement — the same rule Legacy's `checkVerified` applied
    /// when it threw on `.unverified`.
    case transactionUnverified
    /// `AppStore.sync()` (restore) failed.
    case restoreFailed(message: String)
    /// The manage-subscriptions destination cannot be opened on this
    /// platform (no AppKit, no window scene to present from).
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

/// The outcome of a purchase attempt, mirroring StoreKit 2's
/// `Product.PurchaseResult` without exposing StoreKit types. A
/// cancelled or pending purchase is not an error: Legacy ignored
/// both cases, and this target reports them instead of throwing.
public enum PaywallPurchaseOutcome: Equatable, Sendable {
    /// The purchase succeeded, the transaction verified, and
    /// entitlements were refreshed.
    case purchased
    /// The user cancelled before confirming.
    case userCancelled
    /// The purchase is pending (e.g. Ask to Buy); the transaction
    /// listener will pick it up when it completes.
    case pending
}
