import Foundation
import Observation
import StoreKitConfiguration
import StoreKitEngine

/// The in-memory purchase simulator: Legacy's
/// `StoreKitSimulationService` (`Views/Utilities/StoreKit/Services/`),
/// ported to the real `.storekit` format — and, since gap-closure
/// misc, re-implemented over the open StoreKit engine's `AppTestStore`
/// (`frameworks/storekit`, `StoreKitEngine`) instead of the local
/// port Wave 13 landed.
///
/// The engine is the authority now: purchases, renewals, Ask to Buy,
/// refunds, expirations and simulated errors are real engine
/// behaviour against the installed `.storekit` configuration, not
/// hand-rolled state. What the engine does not model stays a
/// session-level overlay and is labelled as such:
/// * Offline mode has no engine equivalent — `isOfflineMode` still
///   blocks purchases locally, before the store is touched.
/// * Family-sharing revocation has no engine API — `revokedProductIDs`
///   is a display overlay on top of engine state (see
///   `triggerRevocation`).
/// * The four scenario profiles are Legacy's; they map onto engine
///   settings overrides (Ask to Buy, simulated network / verification
///   errors) plus the local offline gate.
///
/// This is deliberately NOT `SKTestSession`: that type is the
/// `StoreKitTest` product's `NSObject` test facade (macOS-only) over
/// the same store. The editor session drives the store directly, the
/// way `SKTestSession` does internally, so the session stays portable
/// (the engine is Foundation-only and Linux-buildable).
///
/// Persistence: transactions, entitlements and settings overrides
/// live in the engine's store files under
/// `<cacheDirectory>/<bundleID>/` (`Configuration.storekit`,
/// `store.json`, `overrides.json`). The old local port's
/// `storekit_transactions.json` / `storekit_entitlements.json` files
/// are no longer read; favourites still use `storekit_favorites.json`
/// in the cache directory, as before. With no cache directory the
/// whole session is in-memory.

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

    /// Local gate only: the engine has no offline mode. Purchases are
    /// refused before the store is touched while this is on.
    public var isOfflineMode: Bool = false

    // The three toggles below are backed by engine settings overrides;
    // the setters push the override into the store (and clear it when
    // the toggle goes off), so the store and the UI can never disagree.
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

    /// The configuration installed in the engine's store, if any.
    /// Purchases need one: without it the store has no catalog and
    /// `executePurchase` logs the miss instead of inventing a sale.
    public private(set) var installedConfiguration: StoreConfiguration?

    /// The cache directory the simulator persists to (the engine's
    /// per-app store files plus `storekit_favorites.json`). Nil means
    /// in-memory only.
    public let cacheDirectory: URL?

    /// Products the user revoked through family sharing. The engine
    /// has no family-sharing revocation API, so this is a display
    /// overlay: the records stay in the store, but the session shows
    /// them revoked and their entitlements inactive.
    private var revokedProductIDs: Set<String> = []

    private let device: StoreDevice
    private var store: AppTestStore
    private var bundleID: String

    /// - Parameters:
    ///   - cacheDirectory: engine persistence root; nil keeps
    ///     everything in memory.
    ///   - clock: the store's clock; inject a `ManualClock` in tests
    ///     to move subscription time. Defaults to the system clock.
    ///   - bundleID: the simulated app's bundle identifier; the
    ///     engine keys one store per bundle ID. `installConfiguration`
    ///     re-keys it from the configuration's identifier.
    public init(cacheDirectory: URL? = nil, clock: (any StoreClock)? = nil, bundleID: String = "com.swiftcode.storekit-simulation") {
        self.cacheDirectory = cacheDirectory
        self.bundleID = bundleID
        // Cleaned-up quirks, not the reference's: the editor is a
        // tool, not a parity harness, so a declined Ask-to-Buy
        // request is not delivered and expiring a subscription does
        // not leave a spurious failed transaction behind.
        self.device = StoreDevice(clock: clock ?? SystemClock(), directory: cacheDirectory,
                                  quirks: EngineQuirks(declinedAskToBuyIsDelivered: false, expireLeavesFailedTransaction: false))
        self.store = device.store(for: bundleID)
        log("In-Memory Purchase Simulator Session initialized.")
        loadFavorites()
        refreshFromStore()
    }

    /// Installs a `.storekit` configuration into the engine's store
    /// (what `SKTestSession` creation and the IDE's install-on-Run do)
    /// and re-keys the store from the configuration's identifier, so
    /// one simulated app's transactions do not leak into another's.
    /// Call this whenever the editor loads or edits a configuration;
    /// the installed configuration's own settings (storefront,
    /// timeRate, Ask to Buy) become the store's effective settings.
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

    // MARK: - Engine → session state

    /// Rebuilds the published transactions and entitlements from the
    /// engine's store. Called after every store mutation.
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

    /// Runs the engine's subscription scheduler up to the clock's now
    /// (renewals, grace and retry ends, expirations, in time order)
    /// and refreshes the published state. With the system clock this
    /// is a catch-up; with a `ManualClock` it is time travel for a
    /// subscription under test.
    public func advanceSimulation() {
        store.advance()
        refreshFromStore()
        log("Simulator advanced to the store clock's now.")
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

    // MARK: - Persistence (favourites only; transactions and
    // entitlements live in the engine's store files)

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

    /// Simulates buying a product from the installed configuration,
    /// through the engine. Blocked offline (local gate) or with no
    /// configuration installed; a simulated network or verification
    /// failure is the engine refusing the purchase, logged as such.
    /// With Ask to Buy on, the transaction stays pending in the
    /// engine until a parent approves or declines it. The storefront
    /// is the store's configured storefront; the `storefront`
    /// argument is kept for the old call shape and recorded in the
    /// log, but it does not override the configuration.
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

    /// Family-sharing revocation. The engine has no such API, so this
    /// is a session-level overlay, not an engine transaction: the
    /// records stay in the store, the session shows them revoked and
    /// their entitlements inactive, and `resetSimulator` clears it.
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

    /// Asks the engine to move the subscription into its grace
    /// period at the next failed renewal (grace must be enabled for
    /// it to apply), then reports the engine's real resulting state —
    /// the state only changes once a renewal actually fails, so with
    /// no billing issue outstanding this logs the unchanged state
    /// rather than relabelling it.
    public func simulateGracePeriod(productID: String) {
        store.updateSettings { $0.billingGracePeriodEnabled = true }
        store.advance()
        refreshFromStore()
        let state = transactions.first { $0.productID == productID }?.subscriptionCycleState ?? "Purchase"
        logActivity(category: "Simulation", title: "Entered Grace Period", message: "Billing error triggered. Grace period enabled for '\(productID)'; engine state is now \(state).", details: productID)
    }

    /// Asks the engine to retry billing at the next renewal (retry
    /// must be enabled for it to apply), then reports the engine's
    /// real resulting state.
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

    // MARK: - Favorites & filters

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
