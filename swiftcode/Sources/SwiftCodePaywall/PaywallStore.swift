import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
public final class PaywallStore {
    public static let shared = PaywallStore()

    public private(set) var offers: [PaywallProductOffer] = []

    public private(set) var entitlement = PaywallEntitlementState()

    public var isPro: Bool { entitlement.isPro }

    public private(set) var lastError: PaywallError?

    public private(set) var isLoadingProducts = false

    private let bypass: PaywallBypass

    #if canImport(StoreKit)
    private var liveProducts: [String: Product] = [:]
    private var transactionListener: Task<Void, Never>?
    #endif

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
        lastError = .storeKitUnavailable
        #endif
    }

    public func refreshBypassFlag() {
        entitlement.bypassPaywall = bypass.isEnabled
    }

    public func setDebugProAccess(_ granted: Bool) {
        entitlement.debugOverride = granted
    }

    public func clearDebugOverride() {
        entitlement.debugOverride = nil
    }

    #if canImport(StoreKit)
    private nonisolated static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .verified(safe):
            return safe
        case .unverified:
            throw PaywallError.transactionUnverified
        }
    }

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
