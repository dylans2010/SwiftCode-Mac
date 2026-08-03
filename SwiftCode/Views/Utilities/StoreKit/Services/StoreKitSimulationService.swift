import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.swiftcode.storekit", category: "SimulatorService")

@Observable
@MainActor
public final class StoreKitSimulationService {
    public static let shared = StoreKitSimulationService()

    public private(set) var transactions: [SKTransaction] = []
    public private(set) var entitlements: [SKEntitlement] = []
    public private(set) var activeLogs: [String] = []
    public private(set) var activityEvents: [SKActivityEvent] = []

    // Reusable Simulator Scenario Profiles
    public private(set) var availableProfiles: [SKSimulatorProfile] = [
        SKSimulatorProfile(name: "SaaS Premium Subscriber", desc: "Simulates an active, fully-paid Auto-Renewable SaaS subscriber in USA.", isOffline: false, isAskToBuy: false),
        SKSimulatorProfile(name: "Child Sandbox Account", desc: "Simulates 'Ask to Buy' workflow requiring parent verification.", isOffline: false, isAskToBuy: true),
        SKSimulatorProfile(name: "Offline Airplane Mode", desc: "Simulates zero network connection testing local caches.", isOffline: true, isAskToBuy: false),
        SKSimulatorProfile(name: "JWS Cryptographic Failure", desc: "Forces invalid JWS tokens to verify receipt validation safety.", isOffline: false, isAskToBuy: false, simulateNetworkError: false, failJWSVerification: true)
    ]

    public var selectedProfileID: String = ""

    // Simulator Settings
    public var isOfflineMode: Bool = false
    public var isAskToBuyEnabled: Bool = false
    public var shouldSimulateNetworkFailure: Bool = false
    public var shouldFailVerification: Bool = false

    // Favorites Pinning Lists
    public var favoriteProducts: Set<String> = []
    public var favoriteGroups: Set<String> = []

    // Custom Saved Smart Filters
    public var customFilters: [SKSmartFilter] = [
        SKSmartFilter(name: "Premium Offers Only", minPrice: 9.99, maxPrice: nil, productType: "AutoRenewableSubscription")
    ]

    private init() {
        log("In-Memory Purchase Simulator Session initialized.")
        loadPersistentState()
    }

    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        activeLogs.insert(formatted, at: 0)
        logger.info("\(message, privacy: .public)")

        if activeLogs.count > 300 {
            activeLogs.removeLast()
        }
    }

    public func clearLogs() {
        activeLogs.removeAll()
        log("Console logs cleared.")
    }

    public func logActivity(category: String, title: String, message: String, details: String? = nil) {
        let event = SKActivityEvent(category: category, title: title, message: message, details: details)
        activityEvents.insert(event, at: 0)
        log("[\(category.uppercased())] \(title): \(message)")
    }

    public func clearActivityFeed() {
        activityEvents.removeAll()
        log("Activity feed cleared.")
    }

    private func loadPersistentState() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheURL = urls.first else { return }
        let txFile = cacheURL.appendingPathComponent("storekit_transactions.json")
        let entFile = cacheURL.appendingPathComponent("storekit_entitlements.json")
        let favFile = cacheURL.appendingPathComponent("storekit_favorites.json")

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
        if fileManager.fileExists(atPath: favFile.path) {
            do {
                let data = try Data(contentsOf: favFile)
                let favs = try JSONDecoder().decode([String].self, from: data)
                favoriteProducts = Set(favs)
            } catch {
                favoriteProducts = []
            }
        }
    }

    private func savePersistentState() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheURL = urls.first else { return }
        let txFile = cacheURL.appendingPathComponent("storekit_transactions.json")
        let entFile = cacheURL.appendingPathComponent("storekit_entitlements.json")
        let favFile = cacheURL.appendingPathComponent("storekit_favorites.json")

        do {
            let txData = try JSONEncoder().encode(transactions)
            try txData.write(to: txFile, options: .atomic)
            let entData = try JSONEncoder().encode(entitlements)
            try entData.write(to: entFile, options: .atomic)
            let favData = try JSONEncoder().encode(Array(favoriteProducts))
            try favData.write(to: favFile, options: .atomic)
        } catch {
            log("Error saving simulated state to sandbox cache: \(error.localizedDescription)")
        }
    }

    public func applyProfile(_ profile: SKSimulatorProfile) {
        selectedProfileID = profile.id
        isOfflineMode = profile.isOffline
        isAskToBuyEnabled = profile.isAskToBuy
        shouldSimulateNetworkFailure = profile.simulateNetworkError
        shouldFailVerification = profile.failJWSVerification
        logActivity(category: "Simulation", title: "Profile Applied", message: "Successfully activated simulator profile '\(profile.name)'.")
    }

    public func saveCustomProfile(name: String, desc: String) {
        let p = SKSimulatorProfile(
            name: name,
            desc: desc,
            isOffline: isOfflineMode,
            isAskToBuy: isAskToBuyEnabled,
            simulateNetworkError: shouldSimulateNetworkFailure,
            failJWSVerification: shouldFailVerification
        )
        availableProfiles.append(p)
        logActivity(category: "Simulation", title: "Custom Profile Saved", message: "Saved reusable tester profile '\(name)'.")
    }

    public func executePurchase(productID: String, referenceName: String, price: Double, isSubscription: Bool, duration: String? = nil, storefront: String = "USA") {
        if isOfflineMode {
            logActivity(category: "Simulation", title: "Purchase Blocked", message: "Device is currently offline.", details: productID)
            return
        }
        if shouldSimulateNetworkFailure {
            logActivity(category: "Simulation", title: "Purchase Blocked", message: "Simulated network failure occurred.", details: productID)
            return
        }
        if shouldFailVerification {
            logActivity(category: "Simulation", title: "Purchase Verification Failed", message: "Cryptographic JWS validation signatures mismatched.", details: productID)
            return
        }

        if isAskToBuyEnabled {
            logActivity(category: "Simulation", title: "Ask To Buy Sent", message: "Request sent to organizer for '\(referenceName)'.", details: productID)
            let pendingTx = SKTransaction(
                productID: productID,
                referenceName: referenceName,
                transactionDate: Date(),
                purchaseState: "pending",
                isSubscription: isSubscription,
                storefront: storefront,
                subscriptionCycleState: "Purchase"
            )
            transactions.insert(pendingTx, at: 0)
            savePersistentState()
            return
        }

        let interval: TimeInterval
        switch duration {
        case "P1W": interval = 86400 * 7
        case "P1M": interval = 86400 * 30
        case "P1Y": interval = 86400 * 365
        default: interval = 86400 * 30
        }
        let expiry = isSubscription ? Date().addingTimeInterval(interval) : nil

        let newTx = SKTransaction(
            productID: productID,
            referenceName: referenceName,
            transactionDate: Date(),
            purchaseState: "purchased",
            isSubscription: isSubscription,
            expirationDate: expiry,
            storefront: storefront,
            subscriptionCycleState: "Purchase"
        )
        transactions.insert(newTx, at: 0)

        updateEntitlement(productID: productID, isSubscription: isSubscription, expiry: expiry)
        logActivity(category: "Purchase", title: "Transaction Successful", message: "'\(referenceName)' bought successfully for $\(String(format: "%.2f", price)) via \(storefront).", details: productID)
    }

    public func approvePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        var tx = transactions[idx]
        if tx.purchaseState == "pending" {
            tx.purchaseState = "purchased"
            transactions[idx] = tx

            let expiry = tx.isSubscription ? Date().addingTimeInterval(86400 * 30) : nil
            updateEntitlement(productID: tx.productID, isSubscription: tx.isSubscription, expiry: expiry)
            logActivity(category: "Purchase", title: "Ask To Buy Approved", message: "Organizational manager approved buy request for '\(tx.referenceName)'.", details: tx.productID)
            savePersistentState()
        }
    }

    public func declinePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }) else { return }
        var tx = transactions[idx]
        if tx.purchaseState == "pending" {
            tx.purchaseState = "failed"
            transactions[idx] = tx
            logActivity(category: "Purchase", title: "Ask To Buy Declined", message: "Parental organizer declined payment request for '\(tx.referenceName)'.", details: tx.productID)
            savePersistentState()
        }
    }

    public func triggerRefund(productID: String) {
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID && transactions[idx].purchaseState == "purchased" {
                transactions[idx].purchaseState = "refunded"
                transactions[idx].subscriptionCycleState = "Refunded"
            }
        }
        revokeEntitlement(productID: productID)
        logActivity(category: "Refund", title: "Purchase Refunded", message: "Simulated Apple Support issued refund for '\(productID)'.", details: productID)
    }

    public func triggerRevocation(productID: String) {
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].purchaseState = "revoked"
            }
        }
        revokeEntitlement(productID: productID)
        logActivity(category: "Refund", title: "Family Sharing Revoked", message: "Family organizer sharing privileges disabled for '\(productID)'.", details: productID)
    }

    public func simulateExpiration(productID: String) {
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
            entitlements[idx].expirationDate = Date()
        }
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].subscriptionCycleState = "Expired"
            }
        }
        logActivity(category: "Simulation", title: "Subscription Expired", message: "Timed expiration triggered for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateGracePeriod(productID: String) {
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].subscriptionCycleState = "GracePeriod"
            }
        }
        logActivity(category: "Simulation", title: "Entered Grace Period", message: "Billing error triggered. Entered 16-day grace period for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateBillingRetry(productID: String) {
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].subscriptionCycleState = "BillingRetry"
            }
        }
        logActivity(category: "Simulation", title: "Entered Billing Retry", message: "Billing error continued. Attempting recovery retries for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateRenewal(productID: String) {
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            let nextExpiry = Date().addingTimeInterval(86400 * 30)
            entitlements[idx].isActive = true
            entitlements[idx].expirationDate = nextExpiry
        }
        for idx in 0..<transactions.count {
            if transactions[idx].productID == productID {
                transactions[idx].subscriptionCycleState = "Renewal"
            }
        }
        logActivity(category: "Simulation", title: "Subscription Renewed", message: "Successfully completed recurring billing cycle for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func toggleFavoriteProduct(id: String) {
        if favoriteProducts.contains(id) {
            favoriteProducts.remove(id)
        } else {
            favoriteProducts.insert(id)
        }
        savePersistentState()
    }

    public func addCustomFilter(name: String, minPrice: Double?, maxPrice: Double?, type: String?) {
        let f = SKSmartFilter(name: name, minPrice: minPrice, maxPrice: maxPrice, productType: type)
        customFilters.append(f)
        log("Added smart custom filter '\(name)'.")
    }

    private func updateEntitlement(productID: String, isSubscription: Bool, expiry: Date?) {
        let ent = SKEntitlement(
            productID: productID,
            isSubscription: isSubscription,
            purchaseDate: Date(),
            expirationDate: expiry,
            isActive: true
        )
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx] = ent
        } else {
            entitlements.insert(ent, at: 0)
        }
        savePersistentState()
    }

    private func revokeEntitlement(productID: String) {
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
        }
        savePersistentState()
    }

    public func resetSimulator() {
        transactions.removeAll()
        entitlements.removeAll()
        activeLogs.removeAll()
        activityEvents.removeAll()
        favoriteProducts.removeAll()
        savePersistentState()
        log("Simulator state and persistent caches completely reset.")
    }
}
