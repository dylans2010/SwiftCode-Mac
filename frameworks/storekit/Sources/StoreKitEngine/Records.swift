import Foundation
import StoreKitConfiguration

public enum TransactionState: Int, Codable, Sendable {
    case purchasing = 0
    case purchased = 1
    case failed = 2
    case restored = 3
    case deferred = 4
}

public enum TransactionReason: String, Codable, Sendable {
    case purchase = "PURCHASE"
    case renewal = "RENEWAL"
}

public struct AppliedOffer: Hashable, Codable, Sendable {
    public var type: OfferType
    public var identifier: String?
    public var paymentMode: OfferPaymentMode
    public var period: SubscriptionDuration
    public var priceMilli: Int
}

public struct TransactionRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: UInt64
    public var originalID: UInt64
    public var productID: String
    public var productType: ProductType
    public var subscriptionGroupID: String?
    public var state: TransactionState
    public var reason: TransactionReason
    public var isFinished: Bool
    public var purchaseDate: StoreMilliseconds
    public var originalPurchaseDate: StoreMilliseconds
    public var expiresDate: StoreMilliseconds?
    public var quantity: Int
    public var priceMilli: Int
    public var currency: String
    public var storefront: String
    public var storefrontID: String
    public var appAccountToken: UUID?
    public var offer: AppliedOffer?
    public var isPendingAskToBuy: Bool
    public var isAskToBuyDeclined: Bool
    public var revocationDate: StoreMilliseconds?
    public var revocationReason: Int?
    public var revocationType: String?
    public var revocationPercentage: Int?
    public var hasPurchaseIssue: Bool
    public var isUpgraded: Bool
    public var pendingRequest: PurchaseOptions?

    public var webOrderLineItemID: UInt64 { id }
    public var isRevoked: Bool { revocationDate != nil }
    public var purchase: Date { Date(storeMilliseconds: purchaseDate) }
    public var expiration: Date? { expiresDate.map(Date.init(storeMilliseconds:)) }
}

public enum RenewalState: Int, Codable, Sendable {
    case subscribed = 1
    case expired = 2
    case inBillingRetryPeriod = 3
    case inGracePeriod = 4
    case revoked = 5
}

public struct ContinuingOffer: Hashable, Codable, Sendable {
    public var offer: AppliedOffer
    public var billedPeriod: SubscriptionDuration
    public var remainingPeriods: Int
}

public struct SubscriptionChain: Hashable, Codable, Sendable {
    public var originalID: UInt64
    public var groupID: String
    public var productID: String
    public var autoRenewProductID: String
    public var autoRenewEnabled: Bool
    public var expirationIntent: Int?
    public var state: RenewalState
    public var currentTransactionID: UInt64
    public var originalPurchaseDate: StoreMilliseconds
    public var expiresDate: StoreMilliseconds
    public var recentStartDate: StoreMilliseconds
    public var gracePeriodExpiresDate: StoreMilliseconds?
    public var billingRetryEndDate: StoreMilliseconds?
    public var hasBillingIssue: Bool
    public var continuingOffer: ContinuingOffer?
    public var pendingOffer: ContinuingOffer?
    public var isUpgradedAway: Bool

    public var isActive: Bool { state == .subscribed || state == .inGracePeriod || state == .inBillingRetryPeriod }
    public var isEntitled: Bool { state == .subscribed || state == .inGracePeriod }
}

public struct RenewalSnapshot: Hashable, Sendable {
    public var originalTransactionID: UInt64
    public var productID: String
    public var autoRenewProductID: String
    public var autoRenewStatus: Int
    public var renewalDate: StoreMilliseconds?
    public var renewalPriceMilli: Int?
    public var renewalBillingPlanType: String?
    public var recentSubscriptionStartDate: StoreMilliseconds
    public var isInBillingRetryPeriod: Bool
    public var gracePeriodExpiresDate: StoreMilliseconds?
    public var expirationIntent: Int?
    public var pendingOffer: AppliedOffer?
    public var currency: String
    public var eligibleWinBackOfferIDs: [String]
}

public struct SubscriptionStatusSnapshot: Hashable, Sendable {
    public var state: RenewalState
    public var transaction: TransactionRecord
    public var renewal: RenewalSnapshot
}

public struct SignedPromotionalOffer: Hashable, Codable, Sendable {
    public var offerID: String
    public var keyID: String
    public var nonce: UUID
    public var signature: Data
    public var timestamp: Int64

    public init(offerID: String, keyID: String, nonce: UUID, signature: Data, timestamp: Int64) {
        self.offerID = offerID
        self.keyID = keyID
        self.nonce = nonce
        self.signature = signature
        self.timestamp = timestamp
    }
}

public enum BackdatedRenewalBehavior: String, Hashable, Codable, Sendable {
    case renewUntilNow
    case cancelImmediately
}

public struct PurchaseOptions: Hashable, Codable, Sendable {
    public var quantity: Int
    public var appAccountToken: UUID?
    public var signedPromotionalOffer: SignedPromotionalOffer?
    public var promotionalOfferID: String?
    public var codeOfferReferenceName: String?
    public var purchaseDate: Date?
    public var renewalBehavior: BackdatedRenewalBehavior
    public var custom: [String: String]

    public init(
        quantity: Int = 1, appAccountToken: UUID? = nil, signedPromotionalOffer: SignedPromotionalOffer? = nil,
        promotionalOfferID: String? = nil, codeOfferReferenceName: String? = nil, purchaseDate: Date? = nil,
        renewalBehavior: BackdatedRenewalBehavior = .renewUntilNow, custom: [String: String] = [:]
    ) {
        self.quantity = quantity
        self.appAccountToken = appAccountToken
        self.signedPromotionalOffer = signedPromotionalOffer
        self.promotionalOfferID = promotionalOfferID
        self.codeOfferReferenceName = codeOfferReferenceName
        self.purchaseDate = purchaseDate
        self.renewalBehavior = renewalBehavior
        self.custom = custom
    }
}

public enum PurchaseOutcome: Hashable, Sendable {
    case success(TransactionRecord, isRedelivery: Bool)
    case pending(TransactionRecord)
    case userCancelled

    public var transaction: TransactionRecord? {
        switch self {
        case .success(let t, _), .pending(let t): return t
        case .userCancelled: return nil
        }
    }
}

public enum StoreAPI: String, Codable, Sendable, CaseIterable {
    case loadProducts, purchase, verification, appStoreSync, subscriptionStatus, appTransaction
    case manageSubscriptions, offerCodeRedeem, refundRequest
}

public enum GenericFailure: Hashable, Codable, Sendable {
    case unknown
    case systemError
    case networkError(code: Int)
    case notAvailableInStorefront
    case notEntitled
    case unsupported
    case userCancelled
}

public enum PurchaseFailureReason: String, Hashable, Codable, Sendable, CaseIterable {
    case invalidQuantity, productUnavailable, purchaseNotAllowed, ineligibleForOffer
    case invalidOfferIdentifier, invalidOfferPrice, invalidOfferSignature, missingOfferParameters
}

public enum VerificationFailureReason: String, Hashable, Codable, Sendable, CaseIterable {
    case revokedCertificate, invalidCertificateChain, invalidDeviceVerification, invalidEncoding
    case invalidSignature, missingRequiredProperties
}

public enum RefundRequestFailureReason: String, Hashable, Codable, Sendable, CaseIterable {
    case duplicateRequest, failed
}

public enum SimulatedFailure: Hashable, Codable, Sendable {
    case generic(GenericFailure)
    case purchase(PurchaseFailureReason)
    case verification(VerificationFailureReason)
    case refundRequest(RefundRequestFailureReason)
}

public struct SettingsOverrides: Hashable, Codable, Sendable {
    public var storefront: String?
    public var locale: String?
    public var timeRate: TimeRate?
    public var askToBuyEnabled: Bool?
    public var interruptedPurchasesEnabled: Bool?
    public var billingRetryOnRenewalEnabled: Bool?
    public var billingGracePeriodEnabled: Bool?
    public var disableDialogs: Bool?
    public var failTransactionsEnabled: Bool?
    public var simulatedErrors: [String: SimulatedFailure]

    public init() { simulatedErrors = [:] }
}

public struct EffectiveSettings: Hashable, Sendable {
    public var storefront: Storefront
    public var locale: String
    public var timeRate: TimeRate
    public var askToBuyEnabled: Bool
    public var interruptedPurchasesEnabled: Bool
    public var billingRetryOnRenewalEnabled: Bool
    public var billingGracePeriodEnabled: Bool
    public var disableDialogs: Bool
    public var failTransactionsEnabled: Bool
    public var simulatedErrors: [StoreAPI: SimulatedFailure]

    public var priceLocale: String { storefront.priceLocaleIdentifier(locale: locale) }
}

public struct EngineQuirks: Hashable, Sendable {
    public var declinedAskToBuyIsDelivered: Bool
    public var expireLeavesFailedTransaction: Bool

    public init(declinedAskToBuyIsDelivered: Bool = true, expireLeavesFailedTransaction: Bool = true) {
        self.declinedAskToBuyIsDelivered = declinedAskToBuyIsDelivered
        self.expireLeavesFailedTransaction = expireLeavesFailedTransaction
    }

    public static let reference = EngineQuirks()
    public static let none = EngineQuirks(declinedAskToBuyIsDelivered: false, expireLeavesFailedTransaction: false)
}

public enum StoreEvent: Hashable, Sendable {
    case transaction(TransactionRecord)
    case configurationChanged
    case storefrontChanged(Storefront)
}

public enum StoreKitErrorKind: Hashable, Sendable {
    case unknown
    case userCancelled
    case networkError(code: Int)
    case systemError(SystemErrorReason)
    case notAvailableInStorefront
    case notEntitled
    case unsupported
}

public enum SystemErrorReason: String, Hashable, Sendable {
    case noAccount
    case unknown
}

public struct StoreAlert: Hashable, Sendable {
    public var title: String
    public var message: String
    public static let environmentNote = "[Environment: Xcode]"
}

public struct StoreFailure: Error, Hashable, Sendable {
    public var kind: StoreKitErrorKind
    public var alert: StoreAlert?
    public var record: TransactionRecord?
    public var simulated: SimulatedFailure?

    public init(_ kind: StoreKitErrorKind, alert: StoreAlert? = nil, record: TransactionRecord? = nil, simulated: SimulatedFailure? = nil) {
        self.kind = kind
        self.alert = alert
        self.record = record
        self.simulated = simulated
    }
}

public enum TestErrorCode: Int, Hashable, Sendable {
    case serviceUnavailable = 0
    case invalidProductIdentifier = 1
    case invalidProductType = 2
    case invalidURL = 3
    case fileNotFound = 4
    case noSubscriptionFound = 5
    case noTransactionFound = 6
    case invalidAction = 7
}

public struct TestSessionError: Error, Hashable, Sendable, CustomStringConvertible {
    public var code: TestErrorCode
    public var detail: String

    public init(_ code: TestErrorCode, _ detail: String) {
        self.code = code
        self.detail = detail
    }

    public static let observedDomain = "SKServiceErrorDomain"
    public static let observedCode = 2
    public static let observedUnderlyingDomain = "SKInternalErrorDomain"
    public static let observedUnderlyingCode = 17
    public static let documentedDomain = "SKTestErrorDomain"

    public var description: String { "\(code) (\(code.rawValue)): \(detail)" }
}
