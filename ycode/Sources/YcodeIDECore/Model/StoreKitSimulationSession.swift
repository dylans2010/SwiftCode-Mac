import Foundation
import Observation
import StoreKitConfiguration

/// The in-memory purchase simulator: Legacy's
/// `StoreKitSimulationService` (`Views/Utilities/StoreKit/Services/`),
/// ported to the real `.storekit` format. It simulates purchases against
/// the editor's configuration — it is NOT the StoreKit engine (that is
/// `frameworks/storekit`'s `StoreKitEngine`, owned by the paywall-runtime
/// slice) and it never talks to the App Store: every transaction,
/// entitlement and log entry is local, and the state is the editor's own
/// cache files, as Legacy kept it.
///
/// Subscription expiry uses the file's ISO 8601 renewal period
/// (`SubscriptionDuration`): a week is 7 days, a month 30, a year 365 —
/// the same approximations Legacy's simulator used.

public struct StoreKitSimulatedTransaction: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String
    public var productID: String
    public var referenceName: String
    public var transactionDate: Date
    public var purchaseState: String // purchased, failed, pending, refunded, revoked
    public var ownershipType: String // purchased, familyShared
    public var isSubscription: Bool
    public var expirationDate: Date?
    public var originalTransactionID: String
    public var storefront: String
    public var subscriptionCycleState: String // Purchase, Renewal, GracePeriod, BillingRetry, Expired, Refunded

    public init(
        id: String = UUID().uuidString, productID: String, referenceName: String,
        transactionDate: Date = Date(), purchaseState: String = "purchased",
        ownershipType: String = "purchased", isSubscription: Bool = false,
        expirationDate: Date? = nil, originalTransactionID: String = UUID().uuidString,
        storefront: String = "USA", subscriptionCycleState: String = "Purchase"
    ) {
        self.id = id
        self.productID = productID
        self.referenceName = referenceName
        self.transactionDate = transactionDate
        self.purchaseState = purchaseState
        self.ownershipType = ownershipType
        self.isSubscription = isSubscription
        self.expirationDate = expirationDate
        self.originalTransactionID = originalTransactionID
        self.storefront = storefront
        self.subscriptionCycleState = subscriptionCycleState
    }
}

public struct StoreKitSimulatedEntitlement: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { productID }
    public var productID: String
    public var isSubscription: Bool
    public var purchaseDate: Date
    public var expirationDate: Date?
    public var isActive: Bool

    public init(productID: String, isSubscription: Bool, purchaseDate: Date = Date(),
                expirationDate: Date? = nil, isActive: Bool = true) {
        self.productID = productID
        self.isSubscription = isSubscription
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.isActive = isActive
    }
}

public struct StoreKitActivityEvent: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var timestamp: Date
    public var category: String // Purchase, Refund, Validation, Import, Export, Simulation
    public var title: String
    public var message: String
    public var details: String?

    public init(
        id: String = UUID().uuidString, timestamp: Date = Date(), category: String,
        title: String, message: String, details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.title = title
        self.message = message
        self.details = details
    }
}

/// A reusable simulator scenario (Legacy's `SKSimulatorProfile`).
public struct StoreKitSimulatorProfile: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var desc: String
    public var isOffline: Bool
    public var isAskToBuy: Bool
    public var simulateNetworkError: Bool
    public var failJWSVerification: Bool

    public init(
        id: String = UUID().uuidString, name: String, desc: String,
        isOffline: Bool = false, isAskToBuy: Bool = false,
        simulateNetworkError: Bool = false, failJWSVerification: Bool = false
    ) {
        self.id = id
        self.name = name
        self.desc = desc
        self.isOffline = isOffline
        self.isAskToBuy = isAskToBuy
        self.simulateNetworkError = simulateNetworkError
        self.failJWSVerification = failJWSVerification
    }
}

@MainActor
@Observable
public final class StoreKitSimulationSession {
    public private(set) var transactions: [StoreKitSimulatedTransaction] = []
    public private(set) var entitlements: [StoreKitSimulatedEntitlement] = []
    public private(set) var activeLogs: [String] = []
    public private(set) var activityEvents: [StoreKitActivityEvent] = []

    /// Legacy's four built-in scenario profiles.
    public private(set) var availableProfiles: [StoreKitSimulatorProfile] = [
        StoreKitSimulatorProfile(name: "SaaS Premium Subscriber", desc: "Simulates an active, fully-paid Auto-Renewable SaaS subscriber in USA."),
        StoreKitSimulatorProfile(name: "Child Sandbox Account", desc: "Simulates 'Ask to Buy' workflow requiring parent verification.", isAskToBuy: true),
        StoreKitSimulatorProfile(name: "Offline Airplane Mode", desc: "Simulates zero network connection testing local caches.", isOffline: true),
        StoreKitSimulatorProfile(name: "JWS Cryptographic Failure", desc: "Forces invalid JWS tokens to verify receipt validation safety.", failJWSVerification: true),
    ]

    public var selectedProfileID: String = ""
    public var isOfflineMode: Bool = false
    public var isAskToBuyEnabled: Bool = false
    public var shouldSimulateNetworkFailure: Bool = false
    public var shouldFailVerification: Bool = false

    public var favoriteProducts: Set<String> = []
    public var favoriteGroups: Set<String> = []

    /// The cache directory the simulator persists to (Legacy's
    /// `storekit_transactions.json` / `storekit_entitlements.json` /
    /// `storekit_favorites.json` in the caches directory). Nil disables
    /// persistence (in-memory only); pass the caches directory for the
    /// app's session.
    public let cacheDirectory: URL?

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
        log("In-Memory Purchase Simulator Session initialized.")
        loadPersistentState()
    }

    // MARK: - Logging

    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let formatted = "[\(formatter.string(from: Date()))] \(message)"
        activeLogs.insert(formatted, at: 0)
        if activeLogs.count > 300 { activeLogs.removeLast() }
    }

    public func clearLogs() {
        activeLogs.removeAll()
        log("Console logs cleared.")
    }

    public func logActivity(category: String, title: String, message: String, details: String? = nil) {
        let event = StoreKitActivityEvent(category: category, title: title, message: message, details: details)
        activityEvents.insert(event, at: 0)
        log("[\(category.uppercased())] \(title): \(message)")
    }

    public func clearActivityFeed() {
        activityEvents.removeAll()
        log("Activity feed cleared.")
    }

    // MARK: - Persistence (Legacy's cache files, same names)

    private func loadPersistentState() {
        guard let cacheURL = cacheDirectory else { return }
        let txFile = cacheURL.appendingPathComponent("storekit_transactions.json")
        let entFile = cacheURL.appendingPathComponent("storekit_entitlements.json")
        let favFile = cacheURL.appendingPathComponent("storekit_favorites.json")
        if let data = try? Data(contentsOf: txFile),
           let decoded = try? JSONDecoder().decode([StoreKitSimulatedTransaction].self, from: data) {
            transactions = decoded
            log("Restored \(transactions.count) simulated transactions from sandbox cache.")
        }
        if let data = try? Data(contentsOf: entFile),
           let decoded = try? JSONDecoder().decode([StoreKitSimulatedEntitlement].self, from: data) {
            entitlements = decoded
            log("Restored active entitlements from sandbox cache.")
        }
        if let data = try? Data(contentsOf: favFile),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            favoriteProducts = Set(decoded)
        }
    }

    private func savePersistentState() {
        guard let cacheURL = cacheDirectory else { return }
        do {
            try JSONEncoder().encode(transactions).write(to: cacheURL.appendingPathComponent("storekit_transactions.json"), options: .atomic)
            try JSONEncoder().encode(entitlements).write(to: cacheURL.appendingPathComponent("storekit_entitlements.json"), options: .atomic)
            try JSONEncoder().encode(Array(favoriteProducts)).write(to: cacheURL.appendingPathComponent("storekit_favorites.json"), options: .atomic)
        } catch {
            log("Error saving simulated state to sandbox cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Profiles

    public func applyProfile(_ profile: StoreKitSimulatorProfile) {
        selectedProfileID = profile.id
        isOfflineMode = profile.isOffline
        isAskToBuyEnabled = profile.isAskToBuy
        shouldSimulateNetworkFailure = profile.simulateNetworkError
        shouldFailVerification = profile.failJWSVerification
        logActivity(category: "Simulation", title: "Profile Applied", message: "Successfully activated simulator profile '\(profile.name)'.")
    }

    public func saveCustomProfile(name: String, desc: String) {
        let profile = StoreKitSimulatorProfile(name: name, desc: desc, isOffline: isOfflineMode,
                                               isAskToBuy: isAskToBuyEnabled,
                                               simulateNetworkError: shouldSimulateNetworkFailure,
                                               failJWSVerification: shouldFailVerification)
        availableProfiles.append(profile)
        logActivity(category: "Simulation", title: "Custom Profile Saved", message: "Saved reusable tester profile '\(name)'.")
    }

    // MARK: - Purchases

    /// The expiry of a subscription bought now, from its renewal period.
    public static func expiry(for period: String?, from date: Date = Date()) -> Date? {
        guard let period, let duration = SubscriptionDuration(iso8601: period) else { return nil }
        let days: Int
        switch duration.unit {
        case .day: days = duration.value
        case .week: days = duration.value * 7
        case .month: days = duration.value * 30
        case .year: days = duration.value * 365
        }
        return date.addingTimeInterval(TimeInterval(days * 86400))
    }

    /// Simulates buying a product from the configuration. Blocked offline,
    /// on a simulated network failure, or on a simulated verification
    /// failure; with Ask to Buy on, the transaction stays pending until a
    /// parent approves or declines it.
    public func executePurchase(product: ConfiguredProduct, storefront: String = "USA") {
        let productID = product.productID ?? ""
        let referenceName = product.referenceName ?? productID
        let isSubscription = product.type == .recurringSubscription || product.type == .nonRenewingSubscription
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
            let pending = StoreKitSimulatedTransaction(productID: productID, referenceName: referenceName,
                                                       purchaseState: "pending", isSubscription: isSubscription,
                                                       storefront: storefront)
            transactions.insert(pending, at: 0)
            logActivity(category: "Simulation", title: "Ask To Buy Sent", message: "Request sent to organizer for '\(referenceName)'.", details: productID)
            savePersistentState()
            return
        }
        let expiry = isSubscription ? Self.expiry(for: product.recurringSubscriptionPeriod) : nil
        let transaction = StoreKitSimulatedTransaction(productID: productID, referenceName: referenceName,
                                                       purchaseState: "purchased", isSubscription: isSubscription,
                                                       expirationDate: expiry, storefront: storefront)
        transactions.insert(transaction, at: 0)
        updateEntitlement(productID: productID, isSubscription: isSubscription, expiry: expiry)
        let price = product.displayPrice ?? "0.00"
        logActivity(category: "Purchase", title: "Transaction Successful",
                    message: "'\(referenceName)' bought successfully for $\(price) via \(storefront).", details: productID)
    }

    public func approvePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }), transactions[idx].purchaseState == "pending" else { return }
        transactions[idx].purchaseState = "purchased"
        let tx = transactions[idx]
        let expiry = tx.isSubscription ? Self.expiry(for: "P1M") : nil
        updateEntitlement(productID: tx.productID, isSubscription: tx.isSubscription, expiry: expiry)
        logActivity(category: "Purchase", title: "Ask To Buy Approved", message: "Organizational manager approved buy request for '\(tx.referenceName)'.", details: tx.productID)
        savePersistentState()
    }

    public func declinePendingTransaction(id: String) {
        guard let idx = transactions.firstIndex(where: { $0.id == id }), transactions[idx].purchaseState == "pending" else { return }
        transactions[idx].purchaseState = "failed"
        let tx = transactions[idx]
        logActivity(category: "Purchase", title: "Ask To Buy Declined", message: "Parental organizer declined payment request for '\(tx.referenceName)'.", details: tx.productID)
        savePersistentState()
    }

    public func triggerRefund(productID: String) {
        for idx in transactions.indices where transactions[idx].productID == productID && transactions[idx].purchaseState == "purchased" {
            transactions[idx].purchaseState = "refunded"
            transactions[idx].subscriptionCycleState = "Refunded"
        }
        revokeEntitlement(productID: productID)
        logActivity(category: "Refund", title: "Purchase Refunded", message: "Simulated Apple Support issued refund for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func triggerRevocation(productID: String) {
        for idx in transactions.indices where transactions[idx].productID == productID {
            transactions[idx].purchaseState = "revoked"
        }
        revokeEntitlement(productID: productID)
        logActivity(category: "Refund", title: "Family Sharing Revoked", message: "Family organizer sharing privileges disabled for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateExpiration(productID: String) {
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = false
            entitlements[idx].expirationDate = Date()
        }
        for idx in transactions.indices where transactions[idx].productID == productID {
            transactions[idx].subscriptionCycleState = "Expired"
        }
        logActivity(category: "Simulation", title: "Subscription Expired", message: "Timed expiration triggered for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateGracePeriod(productID: String) {
        for idx in transactions.indices where transactions[idx].productID == productID {
            transactions[idx].subscriptionCycleState = "GracePeriod"
        }
        logActivity(category: "Simulation", title: "Entered Grace Period", message: "Billing error triggered. Entered 16-day grace period for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateBillingRetry(productID: String) {
        for idx in transactions.indices where transactions[idx].productID == productID {
            transactions[idx].subscriptionCycleState = "BillingRetry"
        }
        logActivity(category: "Simulation", title: "Entered Billing Retry", message: "Billing error continued. Attempting recovery retries for '\(productID)'.", details: productID)
        savePersistentState()
    }

    public func simulateRenewal(productID: String) {
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx].isActive = true
            entitlements[idx].expirationDate = Self.expiry(for: "P1M")
        }
        for idx in transactions.indices where transactions[idx].productID == productID {
            transactions[idx].subscriptionCycleState = "Renewal"
        }
        logActivity(category: "Simulation", title: "Subscription Renewed", message: "Successfully completed recurring billing cycle for '\(productID)'.", details: productID)
        savePersistentState()
    }

    // MARK: - Favorites & filters

    public func toggleFavoriteProduct(id: String) {
        if favoriteProducts.contains(id) { favoriteProducts.remove(id) } else { favoriteProducts.insert(id) }
        savePersistentState()
    }

    public func toggleFavoriteGroup(id: String) {
        if favoriteGroups.contains(id) { favoriteGroups.remove(id) } else { favoriteGroups.insert(id) }
    }

    private func updateEntitlement(productID: String, isSubscription: Bool, expiry: Date?) {
        let entitlement = StoreKitSimulatedEntitlement(productID: productID, isSubscription: isSubscription,
                                                       purchaseDate: Date(), expirationDate: expiry, isActive: true)
        if let idx = entitlements.firstIndex(where: { $0.productID == productID }) {
            entitlements[idx] = entitlement
        } else {
            entitlements.insert(entitlement, at: 0)
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
