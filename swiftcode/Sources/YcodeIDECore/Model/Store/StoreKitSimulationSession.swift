import Foundation
import Observation
import StoreKitConfiguration
import StoreKitEngine

public struct StoreKitSimulatedTransaction: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String
    public var productID: String
    public var referenceName: String
    public var transactionDate: Date
    public var purchaseState: String
    public var ownershipType: String
    public var isSubscription: Bool
    public var expirationDate: Date?
    public var originalTransactionID: String
    public var storefront: String
    public var subscriptionCycleState: String

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
    public var category: String
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

    public private(set) var availableProfiles: [StoreKitSimulatorProfile] = [
        StoreKitSimulatorProfile(name: "SaaS Premium Subscriber", desc: "Simulates an active, fully-paid Auto-Renewable SaaS subscriber in USA."),
        StoreKitSimulatorProfile(name: "Child Sandbox Account", desc: "Simulates 'Ask to Buy' workflow requiring parent verification.", isAskToBuy: true),
        StoreKitSimulatorProfile(name: "Offline Airplane Mode", desc: "Simulates zero network connection testing local caches.", isOffline: true),
        StoreKitSimulatorProfile(name: "JWS Cryptographic Failure", desc: "Forces invalid JWS tokens to verify receipt validation safety.", failJWSVerification: true),
    ]

    public var selectedProfileID: String = ""

    public var isOfflineMode: Bool = false

    private var _isAskToBuyEnabled = false
    public var isAskToBuyEnabled: Bool {
        get { _isAskToBuyEnabled }
        set {
            _isAskToBuyEnabled = newValue
            store.updateSettings { $0.askToBuyEnabled = newValue }
        }
    }
    private var _shouldSimulateNetworkFailure = false
    public var shouldSimulateNetworkFailure: Bool {
        get { _shouldSimulateNetworkFailure }
        set {
            _shouldSimulateNetworkFailure = newValue
            store.setSimulatedError(newValue ? .generic(.networkError(code: -1009)) : nil, for: .purchase)
        }
    }
    private var _shouldFailVerification = false
    public var shouldFailVerification: Bool {
        get { _shouldFailVerification }
        set {
            _shouldFailVerification = newValue
            store.setSimulatedError(newValue ? .verification(.invalidSignature) : nil, for: .verification)
        }
    }

    public var favoriteProducts: Set<String> = []
    public var favoriteGroups: Set<String> = []

    public private(set) var installedConfiguration: StoreConfiguration?

    public let cacheDirectory: URL?

    private var revokedProductIDs: Set<String> = []

    private let device: StoreDevice
    private var store: AppTestStore
    private var bundleID: String

    public init(cacheDirectory: URL? = nil, clock: (any StoreClock)? = nil, bundleID: String = "com.swiftcode.storekit-simulation") {
        self.cacheDirectory = cacheDirectory
        self.bundleID = bundleID
        self.device = StoreDevice(clock: clock ?? SystemClock(), directory: cacheDirectory,
                                  quirks: EngineQuirks(declinedAskToBuyIsDelivered: false, expireLeavesFailedTransaction: false))
        self.store = device.store(for: bundleID)
        log("In-Memory Purchase Simulator Session initialized.")
        loadFavorites()
        refreshFromStore()
    }

    public func installConfiguration(_ configuration: StoreConfiguration) {
        let key = "com.swiftcode.storekit-simulation." + (configuration.identifier ?? "default")
        if key != bundleID {
            bundleID = key
            store = device.store(for: bundleID)
        }
        installedConfiguration = configuration
        store.installConfiguration(configuration, appName: ProcessInfo.processInfo.processName)
        _isAskToBuyEnabled = store.settings.askToBuyEnabled
        refreshFromStore()
        log("Installed .storekit configuration '\(configuration.identifier ?? "default")' in the simulator.")
    }

    func refreshFromStore() {
        let records = store.allTransactions()
        transactions = records.map { record in
            StoreKitSimulatedTransaction(
                id: String(record.id),
                productID: record.productID,
                referenceName: store.catalog?.product(record.productID)?.referenceName ?? record.productID,
                transactionDate: record.purchase,
                purchaseState: purchaseState(of: record),
                ownershipType: "purchased",
                isSubscription: record.productType == .autoRenewable || record.productType == .nonRenewable,
                expirationDate: record.expiration,
                originalTransactionID: String(record.originalID),
                storefront: record.storefront,
                subscriptionCycleState: cycleState(of: record)
            )
        }.sorted { $0.transactionDate > $1.transactionDate }
        entitlements = store.currentEntitlements().map { record in
            StoreKitSimulatedEntitlement(
                productID: record.productID,
                isSubscription: record.productType == .autoRenewable || record.productType == .nonRenewable,
                purchaseDate: record.purchase,
                expirationDate: record.expiration,
                isActive: !revokedProductIDs.contains(record.productID)
            )
        }
    }

    private func purchaseState(of record: TransactionRecord) -> String {
        if record.isPendingAskToBuy || record.state == .deferred || record.state == .purchasing { return "pending" }
        if record.isRevoked {
            return record.revocationType == "REFUND_FULL" ? "refunded" : "revoked"
        }
        if revokedProductIDs.contains(record.productID) { return "revoked" }
        switch record.state {
        case .purchased, .restored: return "purchased"
        case .failed: return "failed"
        case .purchasing, .deferred: return "pending"
        }
    }

    private func cycleState(of record: TransactionRecord) -> String {
        if record.isRevoked, record.revocationType == "REFUND_FULL" { return "Refunded" }
        guard let status = store.subscriptionStatus(forTransaction: record.id) else { return "Purchase" }
        switch status.state {
        case .subscribed: return record.reason == .renewal ? "Renewal" : "Purchase"
        case .expired: return "Expired"
        case .inBillingRetryPeriod: return "BillingRetry"
        case .inGracePeriod: return "GracePeriod"
        case .revoked: return "Refunded"
        }
    }

    public func advanceSimulation() {
        store.advance()
        refreshFromStore()
        log("Simulator advanced to the store clock's now.")
    }

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

    private func loadFavorites() {
        guard let cacheURL = cacheDirectory else { return }
        let favFile = cacheURL.appendingPathComponent("storekit_favorites.json")
        if let data = try? Data(contentsOf: favFile),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            favoriteProducts = Set(decoded)
        }
    }

    private func saveFavorites() {
        guard let cacheURL = cacheDirectory else { return }
        do {
            try JSONEncoder().encode(Array(favoriteProducts))
                .write(to: cacheURL.appendingPathComponent("storekit_favorites.json"), options: .atomic)
        } catch {
            log("Error saving favourites to sandbox cache: \(error.localizedDescription)")
        }
    }

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

    public func executePurchase(product: ConfiguredProduct, storefront: String = "USA") {
        let productID = product.productID ?? ""
        let referenceName = product.referenceName ?? productID
        if isOfflineMode {
            logActivity(category: "Simulation", title: "Purchase Blocked", message: "Device is currently offline.", details: productID)
            return
        }
        guard installedConfiguration != nil else {
            logActivity(category: "Simulation", title: "Purchase Blocked", message: "No .storekit configuration is installed in the simulator.", details: productID)
            return
        }
        do {
            let outcome = try store.purchase(productID: productID)
            refreshFromStore()
            switch outcome {
            case .success(let record, _):
                let price = product.displayPrice ?? "0.00"
                logActivity(category: "Purchase", title: "Transaction Successful",
                            message: "'\(referenceName)' bought successfully for $\(price) via \(record.storefront) (requested storefront: \(storefront)).", details: productID)
            case .pending:
                logActivity(category: "Purchase", title: "Ask To Buy Sent", message: "Request sent to organizer for '\(referenceName)'.", details: productID)
            case .userCancelled:
                logActivity(category: "Purchase", title: "Purchase Cancelled", message: "Purchase of '\(referenceName)' was cancelled.", details: productID)
            }
        } catch {
            refreshFromStore()
            if shouldSimulateNetworkFailure {
                logActivity(category: "Simulation", title: "Purchase Blocked", message: "Simulated network failure occurred.", details: productID)
            } else if shouldFailVerification {
                logActivity(category: "Simulation", title: "Purchase Verification Failed", message: "Cryptographic JWS validation signatures mismatched.", details: productID)
            } else {
                logActivity(category: "Purchase", title: "Purchase Failed", message: "\(error)", details: productID)
            }
        }
    }

    private func recordID(_ id: String) -> UInt64? {
        if let numeric = UInt64(id) { return numeric }
        return transactions.first { $0.id == id }.flatMap { UInt64($0.id) }
    }

    public func approvePendingTransaction(id: String) {
        guard let transactionID = recordID(id) else { return }
        do {
            try store.approveAskToBuy(transactionID: transactionID)
            refreshFromStore()
            let tx = transactions.first { $0.id == id }
            logActivity(category: "Purchase", title: "Ask To Buy Approved", message: "Organizational manager approved buy request for '\(tx?.referenceName ?? id)'.", details: tx?.productID ?? id)
        } catch {
            logActivity(category: "Purchase", title: "Ask To Buy Approval Failed", message: "\(error)", details: id)
        }
    }

    public func declinePendingTransaction(id: String) {
        guard let transactionID = recordID(id) else { return }
        do {
            try store.declineAskToBuy(transactionID: transactionID)
            refreshFromStore()
            let tx = transactions.first { $0.id == id }
            logActivity(category: "Purchase", title: "Ask To Buy Declined", message: "Parental organizer declined payment request for '\(tx?.referenceName ?? id)'.", details: tx?.productID ?? id)
        } catch {
            logActivity(category: "Purchase", title: "Ask To Buy Decline Failed", message: "\(error)", details: id)
        }
    }

    public func triggerRefund(productID: String) {
        var refunded = false
        for tx in transactions where tx.productID == productID && tx.purchaseState == "purchased" {
            guard let transactionID = UInt64(tx.id) else { continue }
            do {
                try store.refundTransaction(transactionID)
                refunded = true
            } catch {
                logActivity(category: "Refund", title: "Refund Failed", message: "\(error)", details: productID)
            }
        }
        refreshFromStore()
        if refunded {
            logActivity(category: "Refund", title: "Purchase Refunded", message: "Simulated Apple Support issued refund for '\(productID)'.", details: productID)
        }
    }

    public func triggerRevocation(productID: String) {
        revokedProductIDs.insert(productID)
        refreshFromStore()
        logActivity(category: "Refund", title: "Family Sharing Revoked", message: "Family organizer sharing privileges disabled for '\(productID)'.", details: productID)
    }

    public func simulateExpiration(productID: String) {
        do {
            try store.expireSubscription(productID: productID)
            refreshFromStore()
            logActivity(category: "Simulation", title: "Subscription Expired", message: "Timed expiration triggered for '\(productID)'.", details: productID)
        } catch {
            logActivity(category: "Simulation", title: "Expiration Failed", message: "\(error)", details: productID)
        }
    }

    public func simulateGracePeriod(productID: String) {
        store.updateSettings { $0.billingGracePeriodEnabled = true }
        store.advance()
        refreshFromStore()
        let state = transactions.first { $0.productID == productID }?.subscriptionCycleState ?? "Purchase"
        logActivity(category: "Simulation", title: "Entered Grace Period", message: "Billing error triggered. Grace period enabled for '\(productID)'; engine state is now \(state).", details: productID)
    }

    public func simulateBillingRetry(productID: String) {
        store.updateSettings { $0.billingRetryOnRenewalEnabled = true }
        store.advance()
        refreshFromStore()
        let state = transactions.first { $0.productID == productID }?.subscriptionCycleState ?? "Purchase"
        logActivity(category: "Simulation", title: "Entered Billing Retry", message: "Billing error continued. Billing retry enabled for '\(productID)'; engine state is now \(state).", details: productID)
    }

    public func simulateRenewal(productID: String) {
        do {
            try store.forceRenewal(productID: productID)
            refreshFromStore()
            logActivity(category: "Simulation", title: "Subscription Renewed", message: "Successfully completed recurring billing cycle for '\(productID)'.", details: productID)
        } catch {
            logActivity(category: "Simulation", title: "Renewal Failed", message: "\(error)", details: productID)
        }
    }

    public func toggleFavoriteProduct(id: String) {
        if favoriteProducts.contains(id) { favoriteProducts.remove(id) } else { favoriteProducts.insert(id) }
        saveFavorites()
    }

    public func toggleFavoriteGroup(id: String) {
        if favoriteGroups.contains(id) { favoriteGroups.remove(id) } else { favoriteGroups.insert(id) }
    }

    public func resetSimulator() {
        store.clearTransactions()
        store.resetToDefaultState()
        revokedProductIDs.removeAll()
        _isAskToBuyEnabled = false
        _shouldSimulateNetworkFailure = false
        _shouldFailVerification = false
        isOfflineMode = false
        transactions.removeAll()
        entitlements.removeAll()
        activeLogs.removeAll()
        activityEvents.removeAll()
        favoriteProducts.removeAll()
        saveFavorites()
        refreshFromStore()
        log("Simulator state and persistent caches completely reset.")
    }
}
