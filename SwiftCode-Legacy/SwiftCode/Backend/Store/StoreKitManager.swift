import Foundation
import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()

    private let productIdentifiers = [
        "swiftcode.pro.monthly",
        "swiftcode.pro.yearly",
        "swiftcode.pro.lifetime"
    ]

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await updateCustomerProductStatus()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIdentifiers)
            products.sort { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateCustomerProductStatus()
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await updateCustomerProductStatus()
    }

    func updateCustomerProductStatus() async {
        var purchasedIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchasedIDs.insert(transaction.productID)
            } catch {
                print("Transaction verification failed: \(error)")
            }
        }

        self.purchasedProductIDs = purchasedIDs
        EntitlementManager.shared.updateProStatus(isPro: !purchasedIDs.isEmpty)
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updateCustomerProductStatus()
                    await transaction.finish()
                } catch {
                    print("Transaction update verification failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.notEntitled
        case .verified(let safe):
            return safe
        }
    }
}

enum StoreKitError: Error {
    case notEntitled
}
