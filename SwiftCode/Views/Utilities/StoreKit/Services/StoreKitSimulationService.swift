import Foundation
import Observation

@Observable
@MainActor
public final class StoreKitSimulationService {
    public static let shared = StoreKitSimulationService()

    public private(set) var transactions: [SKTransaction] = []
    public private(set) var entitlements: [SKEntitlement] = []
    public private(set) var activeLogs: [String] = []

    // Simulator Settings
    public var isOfflineMode: Bool = false
    public var isAskToBuyEnabled: Bool = false
    public var shouldSimulateNetworkFailure: Bool = false
    public var shouldFailVerification: Bool = false

    private init() {
        log("In-Memory Purchase Simulator Session initialized.")
        loadPersistentState()
    }

    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        activeLogs.insert("[\(timestamp)] \(message)", at: 0)
        if activeLogs.count > 300 {
            activeLogs.removeLast()
        }
    }

    public func clearLogs() {
        activeLogs.removeAll()
    }

    private func loadPersistentState() {
        // Reads simulated transactions from local sandbox persistence (if any exists)
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheURL = urls.first else { return }
        let txFile = cacheURL.appendingPathComponent("storekit_transactions.json")
        let entFile = cacheURL.appendingPathComponent("storekit_entitlements.json")

        if fileManager.fileExists(atPath: txFile.path) {
            do {
                let data = try Data(contentsOf: txFile)
                transactions = try JSONDecoder().decode([SKTransaction].self, from: data)
                log("Restored \(transactions.count) simulated transactions from sandbox cache.")
            } catch {
                log("Cleared stale simulated transactions cache.")
            }
        }
        if fileManager.fileExists(atPath: entFile.path) {
            do {
                let data = try Data(contentsOf: entFile)
                entitlements = try JSONDecoder().decode([SKEntitlement].self, from: data)
                log("Restored active entitlements from sandbox cache.")
            } catch {
                log("Cleared stale entitlements cache.")
            }
        }
    }

    private func savePersistentState() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheURL = urls.first else { return }
        let txFile = cacheURL.appendingPathComponent("storekit_transactions.json")
        let entFile = cacheURL.appendingPathComponent("storekit_entitlements.json")

        do {
            let txData = try JSONEncoder().encode(transactions)
            try txData.write(to: txFile, options: .atomic)
            let entData = try JSONEncoder().encode(entitlements)
            try entData.write(to: entFile, options: .atomic)
        } catch {
            log("Error saving simulated state to sandbox cache: \(error.localizedDescription)")
        }
    }

    public func executePurchase(productID: String, referenceName: String, price: Double, isSubscription: Bool, duration: String? = nil) {
        if isOfflineMode {
            log("Purchase Failed: Device is currently offline.")
            return
        }
        if shouldSimulateNetworkFailure {
            log("Purchase Failed: Simulated network failure.")
            return
        }
        if shouldFailVerification {
            log("Purchase Failed: Cryptographic receipt verification failed.")
            return
        }

        if isAskToBuyEnabled {
            log("Purchase Pending: 'Ask to Buy' request sent to family organizer for product '\(referenceName)'.")
            let pendingTx = SKTransaction(
                productID: productID,
                referenceName: referenceName,
                transactionDate: Date(),
                purchaseState: "pending",
                isSubscription: isSubscription
            )
            transactions.insert(pendingTx, at: 0)
            savePersistentState()
            return
        }

        log("Purchase Successful: '\(referenceName)' bought for $\(String(format: "%.2f", price)).")

        let expiry: Date?
        if isSubscription {
            let interval: TimeInterval
            switch duration {
            case "P1W": interval = 86400 * 7
            case "P1M": interval = 86400 * 30
            case "P1Y": interval = 86400 * 365
            default: interval = 86400 * 30
            }
            expiry = Date().addingTimeInterval(interval)
        } else {
            expiry = nil
        }

        let newTx = SKTransaction(
            productID: productID,
            referenceName: referenceName,
            transactionDate: Date(),
            purchaseState: "purchased",
            isSubscription: isSubscription,
            expirationDate: expiry
        )
        transactions.insert(newTx, at: 0)

        // Add or update Entitlement
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx] = SKEntitlement(
                productID: productID,
                isSubscription: isSubscription,
                purchaseDate: Date(),
                expirationDate: expiry,
                isActive: true
            )
        } else {
            entitlements.insert(SKEntitlement(
                productID: productID,
                isSubscription: isSubscription,
                purchaseDate: Date(),
                expirationDate: expiry,
                isActive: true
            ), at: 0)
        }

        savePersistentState()
        log("Entitlement Granted: '\(productID)' active.")
    }

    public func approvePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        var tx = transactions[idx]
        if tx.purchaseState == "pending" {
            tx.purchaseState = "purchased"
            transactions[idx] = tx
            log("Transaction '\(id)' Approved via Ask To Buy.")

            let expiry = tx.isSubscription ? Date().addingTimeInterval(86400 * 30) : nil
            let ent = SKEntitlement(productID: tx.productID, isSubscription: tx.isSubscription, purchaseDate: Date(), expirationDate: expiry, isActive: true)
            if let eIdx = entitlements.firstIndex(where: { $0.productID == tx.productID }) {
                entitlements[eIdx] = ent
            } else {
                entitlements.insert(ent, at: 0)
            }
            savePersistentState()
        }
    }

    public func declinePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        var tx = transactions[idx]
        if tx.purchaseState == "pending" {
            tx.purchaseState = "failed"
            transactions[idx] = tx
            log("Transaction '\(id)' Declined/Cancelled via Ask To Buy.")
            savePersistentState()
        }
    }

    public func triggerRefund(productID: String) {
        log("Refunding purchase for product: '\(productID)'.")
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID && transactions[idx].purchaseState == "purchased" {
                transactions[idx].purchaseState = "refunded"
            }
        }
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
            log("Entitlement Revoked for product: '\(productID)'.")
        }
        savePersistentState()
    }

    public func triggerRevocation(productID: String) {
        log("Revoking purchase for product: '\(productID)'.")
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].purchaseState = "revoked"
            }
        }
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
            log("Entitlement Revoked for product: '\(productID)'.")
        }
        savePersistentState()
    }

    public func simulateExpiration(productID: String) {
        log("Simulating subscription expiration for product: '\(productID)'.")
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
            entitlements[idx].expirationDate = Date()
            log("Subscription expired for: '\(productID)'.")
        }
        savePersistentState()
    }

    public func resetSimulator() {
        transactions.removeAll()
        entitlements.removeAll()
        activeLogs.removeAll()
        savePersistentState()
        log("Simulator state completely reset.")
    }
}
