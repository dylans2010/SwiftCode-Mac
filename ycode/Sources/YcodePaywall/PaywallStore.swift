import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

/// The paywall runtime, ported from Legacy's `StoreKitManager`
/// (`SwiftCode/Backend/Store/StoreKitManager.swift`) onto real
/// StoreKit 2. The port is behaviour-for-behaviour:
///
/// - Products are fetched live from the App Store for the catalog
///   IDs (`Product.products(for:)`), cheapest first.
/// - `purchase(_:)` runs the real StoreKit purchase, verifies the
///   transaction, refreshes entitlements, and finishes the
///   transaction. Cancelled and pending purchases are reported as
///   outcomes, not errors (Legacy ignored both cases).
/// - `restorePurchases()` runs `AppStore.sync()` then refreshes.
/// - Entitlements come from `Transaction.currentEntitlements` with
///   StoreKit verification; an unverified transaction is skipped and
///   never grants Pro (Legacy's `checkVerified` threw on
///   `.unverified`).
/// - A detached task observes `Transaction.updates`, verifies each
///   new transaction, refreshes entitlements, and finishes it.
///
/// Differences from Legacy, all deliberate:
/// - No `ObservableObject` / `@Published`: this target must compile
///   on Linux, where Combine does not exist. State is plain stored
///   properties on a `@MainActor` class (the `YcodeCloud`
///   `CloudAuthManager` pattern); SwiftUI views snapshot it.
/// - `lastError` records failures instead of `print`: the paywall
///   view shows it, and tests can assert on it.
/// - Purchase failures are typed (`PaywallError`) instead of
///   propagating the raw StoreKit error.
/// - Where StoreKit does not exist (Linux), every StoreKit operation
///   fails honestly with `PaywallError.storeKitUnavailable` and no
///   entitlement is ever granted. Nothing is faked.
///
/// No receipt, token, or transaction secret is stored or logged
/// anywhere in this target.
@MainActor
public final class PaywallStore {
    public static let shared = PaywallStore()

    /// Live offers from the App Store, cheapest first. Empty until
    /// `loadProducts()` succeeds; prices come only from this fetch.
    public private(set) var offers: [PaywallProductOffer] = []

    /// The current entitlement state (verified entitlements, the
    /// developer bypass flag, and any debug override).
    public private(set) var entitlement = PaywallEntitlementState()

    /// Legacy's `isProUser`.
    public var isPro: Bool { entitlement.isPro }

    /// The most recent failure, if any, for the paywall view to show.
    /// Set by `loadProducts`, `refreshEntitlements`, and the
    /// transaction listener; cleared by a successful refresh.
    public private(set) var lastError: PaywallError?

    /// Whether a product fetch is in flight.
    public private(set) var isLoadingProducts = false

    private let bypass: PaywallBypass

    #if canImport(StoreKit)
    /// Live products keyed by ID, so `purchase(_:)` can run the real
    /// StoreKit purchase for an offer the view is showing.
    private var liveProducts: [String: Product] = [:]
    private var transactionListener: Task<Void, Never>?
    #endif

    /// - Parameter bypass: the developer bypass flag source. Defaults
    ///   to the shared UserDefaults flag.
    /// - Parameter autoStart: when `true` (the default, and Legacy's
    ///   behaviour) the transaction listener starts and products plus
    ///   entitlements load immediately — on Apple platforms, where
    ///   StoreKit exists. Tests pass `false` so no live StoreKit work
    ///   runs and no background refresh can race a debug override.
    public init(bypass: PaywallBypass = PaywallBypass(), autoStart: Bool = true) {
        self.bypass = bypass
        self.entitlement.bypassPaywall = bypass.isEnabled
        guard autoStart else { return }
        #if canImport(StoreKit)
        transactionListener = Self.listenForTransactions(store: self)
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
        #endif
    }

    /// Fetches the catalog products live from the App Store and
    /// stores them cheapest-first. On failure `lastError` is set and
    /// the previous offers are kept.
    public func loadProducts() async {
        #if canImport(StoreKit)
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: PaywallProductCatalog.identifiers)
            liveProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            offers = PaywallProductOffer.sortedByPrice(products.map { product in
                PaywallProductOffer(
                    productID: product.id,
                    displayName: product.displayName,
                    description: product.description,
                    displayPrice: product.displayPrice,
                    price: (product.price as NSDecimalNumber).doubleValue
                )
            })
            if offers.isEmpty {
                lastError = .productsUnavailable
            }
        } catch {
            lastError = .productFetchFailed(message: error.localizedDescription)
        }
        #else
        lastError = .storeKitUnavailable
        #endif
    }

    /// Runs the real StoreKit purchase for an offer from
    /// `loadProducts()`. Returns `.purchased` only after the
    /// transaction verified and entitlements refreshed; the
    /// transaction is finished, as Legacy did.
    public func purchase(_ offer: PaywallProductOffer) async throws -> PaywallPurchaseOutcome {
        #if canImport(StoreKit)
        guard let product = liveProducts[offer.productID] else {
            throw PaywallError.productFetchFailed(
                message: "No live App Store product for \(offer.productID). Load products first."
            )
        }
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw PaywallError.purchaseFailed(message: error.localizedDescription)
        }
        switch result {
        case let .success(verification):
            let transaction = try Self.verify(verification)
            await refreshEntitlements()
            await transaction.finish()
            return .purchased
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
        #else
        throw PaywallError.storeKitUnavailable
        #endif
    }

    /// Re-syncs with the App Store and refreshes entitlements, as
    /// Legacy's `restorePurchases()` did (`AppStore.sync()` first).
    public func restorePurchases() async throws {
        do {
            try await PaywallAppStore.sync()
        } catch let error as PaywallError {
            throw error
        } catch {
            throw PaywallError.restoreFailed(message: error.localizedDescription)
        }
        await refreshEntitlements()
    }

    /// Re-reads the verified current entitlements from the App Store
    /// and rebuilds the entitlement state. This overwrites any debug
    /// override — the same rule Legacy had, where a refresh replaced
    /// whatever the debug views had forced. Unverified transactions
    /// are skipped and recorded in `lastError`.
    public func refreshEntitlements() async {
        #if canImport(StoreKit)
        entitlement.bypassPaywall = bypass.isEnabled
        var purchasedIDs = Set<String>()
        var verificationFailed = false
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.verify(result)
                purchasedIDs.insert(transaction.productID)
            } catch {
                verificationFailed = true
            }
        }
        entitlement.purchasedProductIDs = purchasedIDs
        entitlement.debugOverride = nil
        lastError = verificationFailed ? .transactionUnverified : nil
        #else
        // Without StoreKit there is nothing to verify against, so the
        // state is left exactly as it is (including any debug
        // override) and the missing framework is recorded.
        lastError = .storeKitUnavailable
        #endif
    }

    /// Re-reads the developer bypass flag into the entitlement state,
    /// as Legacy's `FeatureFlags` did via `didSet` calling
    /// `updateProStatus`. Takes effect immediately, without a store
    /// round-trip.
    public func refreshBypassFlag() {
        entitlement.bypassPaywall = bypass.isEnabled
    }

    // MARK: - Debug-only

    /// Forces the Pro flag on or off, exactly as Legacy's debug views
    /// did through `EntitlementManager.updateProStatus(isPro:)`.
    /// This creates no transaction and no entitlement: it only sets
    /// the debug override, which the next real entitlement refresh
    /// overwrites. The debug views label it as a forced value.
    public func setDebugProAccess(_ granted: Bool) {
        entitlement.debugOverride = granted
    }

    /// Drops the debug override so the flag follows real entitlements
    /// and the bypass flag again.
    public func clearDebugOverride() {
        entitlement.debugOverride = nil
    }

    // MARK: - StoreKit helpers

    #if canImport(StoreKit)
    /// Legacy's `checkVerified`: a verified result yields the value,
    /// an unverified one is rejected — it never grants an entitlement.
    private nonisolated static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(safe):
            return safe
        case .unverified:
            throw PaywallError.transactionUnverified
        }
    }

    /// Legacy's `listenForTransactions`: a detached task observing
    /// `Transaction.updates`, verifying each new transaction,
    /// refreshing entitlements, and finishing it.
    private nonisolated static func listenForTransactions(store: PaywallStore) -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try verify(result)
                    await store.refreshEntitlements()
                    await transaction.finish()
                } catch {
                    await store.recordTransactionError()
                }
            }
        }
    }

    private func recordTransactionError() {
        lastError = .transactionUnverified
    }
    #endif
}
