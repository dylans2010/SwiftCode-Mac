import Foundation
@_spi(SwiftCode) import StoreKit
import StoreKitConfiguration
import StoreKitEngine

public struct SKTestError: CustomNSError, Hashable, Sendable {
    public enum Code: Int, Hashable, Sendable {
        case serviceUnavailable = 0, invalidProductIdentifier, invalidProductType, invalidURL, fileNotFound
        case noSubscriptionFound, noTransactionFound, invalidAction
    }

    public let code: Code
    public let detail: String

    public init(_ code: Code, detail: String = "") {
        self.code = code
        self.detail = detail
    }

    init(_ e: TestSessionError) { self.init(Code(rawValue: e.code.rawValue) ?? .invalidAction, detail: e.detail) }

    public static let errorDomain = "SKTestErrorDomain"
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: detail] }

    public var swiftcodeObservedError: NSError {
        NSError(domain: TestSessionError.observedDomain, code: TestSessionError.observedCode, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: TestSessionError.observedUnderlyingDomain, code: TestSessionError.observedUnderlyingCode),
            "client-environment-type": "Xcode",
        ])
    }
}

open class SKTestTransaction: NSObject, @unchecked Sendable {
    public let identifier: UInt
    public let productIdentifier: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let cancelDate: Date?
    public let state: SKPaymentTransactionState
    public let hasPurchaseIssue: Bool
    public let pendingAskToBuyConfirmation: Bool
    public let autoRenewingEnabled: Bool
    public let pendingPriceIncreaseConsent = false
    public let originalTransactionIdentifier: UInt

    init(_ r: TransactionRecord, autoRenewing: Bool) {
        identifier = UInt(r.id)
        productIdentifier = r.productID
        purchaseDate = r.purchase
        expirationDate = r.expiration
        cancelDate = r.revocationDate.map(Date.init(storeMilliseconds:))
        state = SKPaymentTransactionState(rawValue: r.state.rawValue) ?? .failed
        hasPurchaseIssue = r.hasPurchaseIssue
        pendingAskToBuyConfirmation = r.isPendingAskToBuy
        autoRenewingEnabled = autoRenewing
        originalTransactionIdentifier = r.originalID == r.id ? 0 : UInt(r.originalID)
    }
}

open class SKTestSession: NSObject, @unchecked Sendable {
    public enum TimeRate: Int, Sendable, CaseIterable {
        case realTime = 0
        case oneHourIsOneDay = 1, thirtyMinutesIsOneDay = 2, fiveMinutesIsOneDay = 3, oneMinuteIsOneDay = 4
        case thirtySecondsIsOneDay = 5, oneSecondIsOneDay = 6
        case monthlyRenewalEveryHour = 10, monthlyRenewalEveryThirtyMinutes = 11, monthlyRenewalEveryFifteenMinutes = 12
        case monthlyRenewalEveryFiveMinutes = 13, monthlyRenewalEveryThirtySeconds = 15
        case oneRenewalEveryFifteenMinutes = 1000, oneRenewalEveryFiveMinutes = 1001, oneRenewalEveryMinute = 1002
        case oneRenewalEveryThirtySeconds = 1003, oneRenewalEveryTenSeconds = 1004, oneRenewalEveryTwoSeconds = 1005
    }

    let runtime: SwiftCodeStoreKit
    var store: AppTestStore { runtime.store }

    public convenience init(configurationFileNamed name: String) throws {
        let bundles = [Bundle.main] + Bundle.allBundles
        guard let url = bundles.lazy.compactMap({ $0.url(forResource: name, withExtension: "storekit") }).first else {
            throw SKTestError(.fileNotFound, detail: "No \(name).storekit in the app's bundles.")
        }
        try self.init(contentsOf: url)
    }

    public init(contentsOf url: URL) throws {
        guard url.isFileURL else { throw SKTestError(.invalidURL, detail: "\(url) is not a file URL.") }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SKTestError(.fileNotFound, detail: "No file at \(url.path).")
        }
        let configuration: StoreConfiguration
        do { configuration = try StoreConfiguration(contentsOf: url) } catch {
            throw SKTestError(.invalidURL, detail: "\(url.lastPathComponent) is not a StoreKit configuration (\(error)).")
        }
        runtime = SwiftCodeStoreKit.shared
        super.init()
        runtime.store.installConfiguration(configuration, appName: ProcessInfo.processInfo.processName)
    }

    open var storefront: String {
        get { store.settings.storefront.countryCode }
        set { store.updateSettings { $0.storefront = newValue } }
    }

    open var locale: Locale {
        get { Locale(identifier: store.settings.locale) }
        set { store.updateSettings { $0.locale = newValue.identifier } }
    }

    open var timeRate: TimeRate {
        get { TimeRate(rawValue: store.settings.timeRate.rawValue) ?? .realTime }
        set { store.updateSettings { $0.timeRate = StoreKitEngine.TimeRate(rawValue: newValue.rawValue) } }
    }

    open var askToBuyEnabled: Bool {
        get { store.settings.askToBuyEnabled }
        set { store.updateSettings { $0.askToBuyEnabled = newValue } }
    }

    open var disableDialogs: Bool {
        get { store.settings.disableDialogs }
        set { store.updateSettings { $0.disableDialogs = newValue } }
    }

    open var interruptedPurchasesEnabled: Bool {
        get { store.settings.interruptedPurchasesEnabled }
        set { store.updateSettings { $0.interruptedPurchasesEnabled = newValue } }
    }

    open var shouldEnterBillingRetryOnRenewal: Bool {
        get { store.settings.billingRetryOnRenewalEnabled }
        set { store.updateSettings { $0.billingRetryOnRenewalEnabled = newValue } }
    }

    open var billingGracePeriodIsEnabled: Bool {
        get { store.settings.billingGracePeriodEnabled }
        set { store.updateSettings { $0.billingGracePeriodEnabled = newValue } }
    }

    open var failTransactionsEnabled: Bool {
        get { store.settings.failTransactionsEnabled }
        set { store.updateSettings { $0.failTransactionsEnabled = newValue } }
    }

    private func control(_ body: () throws(TestSessionError) -> Void) throws {
        do { try body() } catch { throw SKTestError(error) }
    }

    open func allTransactions() -> [SKTestTransaction] {
        store.allTransactions().map { r in
            let renewing = r.productType == .autoRenewable
                ? store.subscriptionStatus(forTransaction: r.id)?.renewal.autoRenewStatus == 1 : false
            return SKTestTransaction(r, autoRenewing: renewing)
        }
    }

    open func clearTransactions() { store.clearTransactions() }

    open func resetToDefaultState() { store.resetToDefaultState() }

    open func deleteTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.deleteTransaction(UInt64(identifier)) }
    }

    open func refundTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.refundTransaction(UInt64(identifier)) }
    }

    open func expireSubscription(productIdentifier: String) throws {
        try control { () throws(TestSessionError) in try store.expireSubscription(productID: productIdentifier) }
    }

    open func forceRenewalOfSubscription(productIdentifier: String) throws {
        try control { () throws(TestSessionError) in try store.forceRenewal(productID: productIdentifier) }
    }

    open func disableAutoRenewForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.disableAutoRenew(transactionID: UInt64(identifier)) }
    }

    open func enableAutoRenewForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.enableAutoRenew(transactionID: UInt64(identifier)) }
    }

    open func approveAskToBuyTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.approveAskToBuy(transactionID: UInt64(identifier)) }
    }

    open func declineAskToBuyTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.declineAskToBuy(transactionID: UInt64(identifier)) }
    }

    open func resolveIssueForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.resolveIssue(transactionID: UInt64(identifier)) }
    }

    open func requestPriceIncreaseConsentForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.requestPriceIncreaseConsent(transactionID: UInt64(identifier)) }
    }

    open func consentToPriceIncreaseForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.consentToPriceIncrease(transactionID: UInt64(identifier)) }
    }

    open func declinePriceIncreaseForTransaction(identifier: UInt) throws {
        try control { () throws(TestSessionError) in try store.declinePriceIncrease(transactionID: UInt64(identifier)) }
    }

    open func buyProduct(productIdentifier: String) throws {
        try control { () throws(TestSessionError) in _ = try store.buyProduct(productID: productIdentifier) }
    }

    @discardableResult
    public func buyProduct(identifier: String, options: Set<Product.PurchaseOption> = []) async throws -> Transaction {
        var o = PurchaseOptions()
        for option in options {
            switch option.kind {
            case .appAccountToken(let t): o.appAccountToken = t
            case .quantity(let q): o.quantity = q
            case .custom(let k, let v): o.custom[k] = v
            case .unsignedPromotionalOffer(let id): o.promotionalOfferID = id
            case .codeOffer(let code): o.codeOfferReferenceName = code
            case .purchaseDate(let d, let b):
                o.purchaseDate = d
                o.renewalBehavior = b
            case .signedPromotionalOffer(let id, let key, let nonce, let sig, let ts):
                o.signedPromotionalOffer = SignedPromotionalOffer(offerID: id, keyID: key, nonce: nonce, signature: sig, timestamp: Int64(ts))
            case .simulatesAskToBuyInSandbox: break
            }
        }
        let record: TransactionRecord
        do { record = try store.buyProduct(productID: identifier, options: o) } catch { throw SKTestError(error) }
        guard let result = await Transaction.swiftcodeVerified(record) else { throw SKTestError(.invalidAction, detail: "signing failed") }
        return result.unsafePayloadValue
    }

    public func setSimulatedError<API: FailableStoreKitAPI>(_ error: API.Failure?, forAPI api: API) async {
        store.setSimulatedError(error?.swiftcodeFailure, for: api.swiftcodeAPI)
    }

    public func simulatedError<API: FailableStoreKitAPI>(forAPI api: API) async -> API.Failure? {
        store.simulatedError(for: api.swiftcodeAPI).flatMap(API.Failure.init(swiftcode:))
    }
}

extension Product.PurchaseOption {
    public enum SubscriptionRenewalBehavior: Hashable, Sendable, Codable {
        case renewUntilNow, cancelImmediately
    }

    public static func promotionalOffer(id: String) -> Product.PurchaseOption { .init(kind: .unsignedPromotionalOffer(id)) }

    public static func codeOffer(referenceName: String) -> Product.PurchaseOption { .init(kind: .codeOffer(referenceName)) }

    public static func purchaseDate(_ date: Date, renewalBehavior: SubscriptionRenewalBehavior = .renewUntilNow) -> Product.PurchaseOption {
        .init(kind: .purchaseDate(date, renewalBehavior == .renewUntilNow ? .renewUntilNow : .cancelImmediately))
    }
}
