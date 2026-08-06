import Foundation

// MARK: - StoreKit Config Schema (Compatible with Xcode .storekit files)

public struct StoreKitConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: String { identifier }
    public var identifier: String
    public var settings: SKSettings
    public var products: [SKProduct]
    public var subscriptionGroups: [SKSubscriptionGroup]
    public var nonRenewingSubscriptions: [SKNonRenewingSubscription]
    public var version: [Int]

    public init(
        identifier: String = UUID().uuidString,
        settings: SKSettings = SKSettings(),
        products: [SKProduct] = [],
        subscriptionGroups: [SKSubscriptionGroup] = [],
        nonRenewingSubscriptions: [SKNonRenewingSubscription] = [],
        version: [Int] = [4, 0]
    ) {
        self.identifier = identifier
        self.settings = settings
        self.products = products
        self.subscriptionGroups = subscriptionGroups
        self.nonRenewingSubscriptions = nonRenewingSubscriptions
        self.version = version
    }
}

// MARK: - Settings

public struct SKSettings: Codable, Sendable, Equatable {
    public var _billingGracePeriodEnabled: Bool
    public var _billingRetryEnabled: Bool
    public var _failTransactionsEnabled: Bool
    public var _storeKitError: String?
    public var _locale: String
    public var _storefront: String
    public var _timeRate: String // e.g., "Monthly" or "Weekly"

    enum CodingKeys: String, CodingKey {
        case _billingGracePeriodEnabled = "billingGracePeriodEnabled"
        case _billingRetryEnabled = "billingRetryEnabled"
        case _failTransactionsEnabled = "failTransactionsEnabled"
        case _storeKitError = "storeKitError"
        case _locale = "locale"
        case _storefront = "storefront"
        case _timeRate = "timeRate"
    }

    public init(
        billingGracePeriodEnabled: Bool = false,
        billingRetryEnabled: Bool = false,
        failTransactionsEnabled: Bool = false,
        storeKitError: String? = nil,
        locale: String = "en_US",
        storefront: String = "USA",
        timeRate: String = "none"
    ) {
        self._billingGracePeriodEnabled = billingGracePeriodEnabled
        self._billingRetryEnabled = billingRetryEnabled
        self._failTransactionsEnabled = failTransactionsEnabled
        self._storeKitError = storeKitError
        self._locale = locale
        self._storefront = storefront
        self._timeRate = timeRate
    }
}

// MARK: - Localizations

public struct SKLocalization: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { locale }
    public var locale: String // e.g. "en_US", "fr_FR"
    public var displayName: String
    public var description: String

    public init(locale: String, displayName: String, description: String) {
        self.locale = locale
        self.displayName = displayName
        self.description = description
    }
}

// MARK: - In-App Product (Consumables, Non-Consumables)

public struct SKProduct: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { productID }
    public var productID: String
    public var referenceName: String
    public var type: String // "Consumable", "NonConsumable"
    public var localizations: [SKLocalization]
    public var price: Double
    public var familySharing: Bool
    public var index: Int? // Order index
    public var availability: String // "all", "none"
    public var images: [String] // Local asset image names

    enum CodingKeys: String, CodingKey {
        case productID
        case referenceName
        case type
        case localizations
        case price
        case familySharing
    }

    public init(
        productID: String,
        referenceName: String,
        type: String = "NonConsumable",
        localizations: [SKLocalization] = [],
        price: Double = 0.99,
        familySharing: Bool = false,
        index: Int? = nil,
        availability: String = "all",
        images: [String] = []
    ) {
        self.productID = productID
        self.referenceName = referenceName
        self.type = type
        self.localizations = localizations
        self.price = price
        self.familySharing = familySharing
        self.index = index
        self.availability = availability
        self.images = images
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        referenceName = try container.decode(String.self, forKey: .referenceName)
        type = try container.decode(String.self, forKey: .type)
        localizations = try container.decode([SKLocalization].self, forKey: .localizations)
        price = try container.decode(Double.self, forKey: .price)
        familySharing = try container.decode(Bool.self, forKey: .familySharing)
        index = nil
        availability = "all"
        images = []
    }
}

// MARK: - Non-Renewing Subscription

public struct SKNonRenewingSubscription: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { productID }
    public var productID: String
    public var referenceName: String
    public var type: String = "NonRenewingSubscription"
    public var localizations: [SKLocalization]
    public var price: Double
    public var familySharing: Bool
    public var index: Int?
    public var availability: String

    enum CodingKeys: String, CodingKey {
        case productID
        case referenceName
        case type
        case localizations
        case price
        case familySharing
    }

    public init(
        productID: String,
        referenceName: String,
        localizations: [SKLocalization] = [],
        price: Double = 4.99,
        familySharing: Bool = false,
        index: Int? = nil,
        availability: String = "all"
    ) {
        self.productID = productID
        self.referenceName = referenceName
        self.localizations = localizations
        self.price = price
        self.familySharing = familySharing
        self.index = index
        self.availability = availability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        referenceName = try container.decode(String.self, forKey: .referenceName)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "NonRenewingSubscription"
        localizations = try container.decode([SKLocalization].self, forKey: .localizations)
        price = try container.decode(Double.self, forKey: .price)
        familySharing = try container.decode(Bool.self, forKey: .familySharing)
        index = nil
        availability = "all"
    }
}

// MARK: - Subscription Group

public struct SKSubscriptionGroup: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String
    public var referenceName: String
    public var localizations: [SKLocalization]
    public var subscriptions: [SKSubscription]

    public var groupName: String {
        get { referenceName }
        set { referenceName = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case referenceName
        case localizations
        case subscriptions
    }

    public init(id: String = UUID().uuidString, referenceName: String, localizations: [SKLocalization] = [], subscriptions: [SKSubscription] = []) {
        self.id = id
        self.referenceName = referenceName
        self.localizations = localizations
        self.subscriptions = subscriptions
    }

    public init(groupName: String, subscriptions: [SKSubscription] = []) {
        self.id = UUID().uuidString
        self.referenceName = groupName
        self.localizations = []
        self.subscriptions = subscriptions
    }
}

// MARK: - Auto-Renewing Subscription

public struct SKSubscription: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { productID }
    public var productID: String
    public var referenceName: String
    public var type: String = "AutoRenewableSubscription"
    public var localizations: [SKLocalization]
    public var price: Double
    public var familySharing: Bool
    public var subscriptionGroupID: String
    public var subscriptionPeriod: String // "P1M", "P1Y", "P1W" etc.
    public var index: Int?
    public var availability: String

    // Offers
    public var introductoryOffers: [SKIntroductoryOffer]
    public var promotionalOffers: [SKPromotionalOffer]
    public var winBackOffers: [SKWinBackOffer]
    public var offerCodes: [SKOfferCode]

    enum CodingKeys: String, CodingKey {
        case productID
        case referenceName
        case type
        case localizations
        case price
        case familySharing
        case subscriptionGroupID
        case subscriptionPeriod
        case introductoryOffers
        case promotionalOffers
        case winBackOffers
        case offerCodes
    }

    public init(
        productID: String,
        referenceName: String,
        localizations: [SKLocalization] = [],
        price: Double = 9.99,
        familySharing: Bool = false,
        subscriptionGroupID: String,
        subscriptionPeriod: String = "P1M",
        index: Int? = nil,
        availability: String = "all",
        introductoryOffers: [SKIntroductoryOffer] = [],
        promotionalOffers: [SKPromotionalOffer] = [],
        winBackOffers: [SKWinBackOffer] = [],
        offerCodes: [SKOfferCode] = []
    ) {
        self.productID = productID
        self.referenceName = referenceName
        self.localizations = localizations
        self.price = price
        self.familySharing = familySharing
        self.subscriptionGroupID = subscriptionGroupID
        self.subscriptionPeriod = subscriptionPeriod
        self.index = index
        self.availability = availability
        self.introductoryOffers = introductoryOffers
        self.promotionalOffers = promotionalOffers
        self.winBackOffers = winBackOffers
        self.offerCodes = offerCodes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        referenceName = try container.decode(String.self, forKey: .referenceName)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "AutoRenewableSubscription"
        localizations = try container.decode([SKLocalization].self, forKey: .localizations)
        price = try container.decode(Double.self, forKey: .price)
        familySharing = try container.decode(Bool.self, forKey: .familySharing)
        subscriptionGroupID = try container.decode(String.self, forKey: .subscriptionGroupID)
        subscriptionPeriod = try container.decode(String.self, forKey: .subscriptionPeriod)
        introductoryOffers = try container.decodeIfPresent([SKIntroductoryOffer].self, forKey: .introductoryOffers) ?? []
        promotionalOffers = try container.decodeIfPresent([SKPromotionalOffer].self, forKey: .promotionalOffers) ?? []
        winBackOffers = try container.decodeIfPresent([SKWinBackOffer].self, forKey: .winBackOffers) ?? []
        offerCodes = try container.decodeIfPresent([SKOfferCode].self, forKey: .offerCodes) ?? []
        index = nil
        availability = "all"
    }
}

// MARK: - Introductory Offer

public struct SKIntroductoryOffer: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { paymentMode + "_" + subscriptionPeriod }
    public var numberOfPeriods: Int
    public var paymentMode: String // "payAsYouGo", "payUpFront", "freeTrial"
    public var price: Double
    public var subscriptionPeriod: String // "P1W", "P1M", etc.

    public init(numberOfPeriods: Int = 1, paymentMode: String = "freeTrial", price: Double = 0.0, subscriptionPeriod: String = "P1W") {
        self.numberOfPeriods = numberOfPeriods
        self.paymentMode = paymentMode
        self.price = price
        self.subscriptionPeriod = subscriptionPeriod
    }
}

// MARK: - Promotional Offer

public struct SKPromotionalOffer: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { offerID }
    public var offerID: String
    public var referenceName: String
    public var paymentMode: String // "payAsYouGo", "payUpFront", "freeTrial"
    public var price: Double
    public var numberOfPeriods: Int
    public var subscriptionPeriod: String

    public init(offerID: String, referenceName: String, paymentMode: String = "payAsYouGo", price: Double = 0.99, numberOfPeriods: Int = 1, subscriptionPeriod: String = "P1M") {
        self.offerID = offerID
        self.referenceName = referenceName
        self.paymentMode = paymentMode
        self.price = price
        self.numberOfPeriods = numberOfPeriods
        self.subscriptionPeriod = subscriptionPeriod
    }
}

// MARK: - Win Back Offer

public struct SKWinBackOffer: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { offerID }
    public var offerID: String
    public var referenceName: String
    public var paymentMode: String
    public var price: Double
    public var numberOfPeriods: Int
    public var subscriptionPeriod: String

    public init(offerID: String, referenceName: String, paymentMode: String = "freeTrial", price: Double = 0.0, numberOfPeriods: Int = 1, subscriptionPeriod: String = "P1M") {
        self.offerID = offerID
        self.referenceName = referenceName
        self.paymentMode = paymentMode
        self.price = price
        self.numberOfPeriods = numberOfPeriods
        self.subscriptionPeriod = subscriptionPeriod
    }
}

// MARK: - Offer Code

public struct SKOfferCode: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { code }
    public var code: String
    public var referenceName: String
    public var customerEligibility: String // "new", "existing", "all"
    public var expirationDate: String? // "YYYY-MM-DD"

    public init(code: String, referenceName: String, customerEligibility: String = "all", expirationDate: String? = nil) {
        self.code = code
        self.referenceName = referenceName
        self.customerEligibility = customerEligibility
        self.expirationDate = expirationDate
    }
}

// MARK: - Storefront

public struct SKStorefront: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { code }
    public var code: String // e.g., "USA", "CAN", "FRA", "GBR", "JPN"
    public var name: String
    public var region: String // "North America", "Europe", "Asia", etc.
    public var currency: String // "USD", "CAD", "EUR", "GBP", "JPY"
    public var isAvailable: Bool

    public init(code: String, name: String, region: String, currency: String, isAvailable: Bool = true) {
        self.code = code
        self.name = name
        self.region = region
        self.currency = currency
        self.isAvailable = isAvailable
    }
}

// MARK: - Simulator Support Models

public struct SKTransaction: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String
    public var productID: String
    public var referenceName: String
    public var transactionDate: Date
    public var purchaseState: String // "purchased", "failed", "pending", "refunded", "revoked"
    public var ownershipType: String // "purchased", "familyShared"
    public var isSubscription: Bool
    public var expirationDate: Date?
    public var originalTransactionID: String
    public var storefront: String
    public var subscriptionCycleState: String // "Purchase", "Renewal", "GracePeriod", "BillingRetry", "Expired", "Refunded"

    public init(
        id: String = UUID().uuidString,
        productID: String,
        referenceName: String,
        transactionDate: Date = Date(),
        purchaseState: String = "purchased",
        ownershipType: String = "purchased",
        isSubscription: Bool = false,
        expirationDate: Date? = nil,
        originalTransactionID: String = UUID().uuidString,
        storefront: String = "USA",
        subscriptionCycleState: String = "Purchase"
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

public struct SKEntitlement: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: String { productID }
    public var productID: String
    public var isSubscription: Bool
    public var purchaseDate: Date
    public var expirationDate: Date?
    public var isActive: Bool

    public init(productID: String, isSubscription: Bool, purchaseDate: Date = Date(), expirationDate: Date? = nil, isActive: Bool = true) {
        self.productID = productID
        self.isSubscription = isSubscription
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.isActive = isActive
    }
}

public struct SKAsset: Codable, Sendable, Identifiable, Hashable {
    public var id: String { resolvedPath }
    public let fileName: String
    public let resolvedPath: String
    public let size: String
    public let type: String

    public init(fileName: String, resolvedPath: String, size: String, type: String) {
        self.fileName = fileName
        self.resolvedPath = resolvedPath
        self.size = size
        self.type = type
    }
}

// MARK: - Reusable Simulator Testing Profiles

public struct SKSimulatorProfile: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var desc: String
    public var isOffline: Bool
    public var isAskToBuy: Bool
    public var simulateNetworkError: Bool
    public var failJWSVerification: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        desc: String,
        isOffline: Bool = false,
        isAskToBuy: Bool = false,
        simulateNetworkError: Bool = false,
        failJWSVerification: Bool = false
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

// MARK: - Activity Timeline & Simulation Event Log

public struct SKActivityEvent: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var timestamp: Date
    public var category: String // "Purchase", "Refund", "Validation", "Import", "Export", "Simulation"
    public var title: String
    public var message: String
    public var details: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        category: String,
        title: String,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.title = title
        self.message = message
        self.details = details
    }
}

// MARK: - Version Revision Snapshots

public struct SKVersionRevision: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var timestamp: Date
    public var reason: String
    public var config: StoreKitConfig

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        reason: String,
        config: StoreKitConfig
    ) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
        self.config = config
    }
}

// MARK: - Smart Saved Filter

public struct SKSmartFilter: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var minPrice: Double?
    public var maxPrice: Double?
    public var productType: String? // "Consumable", "NonConsumable", "AutoRenewableSubscription", "NonRenewingSubscription"

    public init(
        id: String = UUID().uuidString,
        name: String,
        minPrice: Double? = nil,
        maxPrice: Double? = nil,
        productType: String? = nil
    ) {
        self.id = id
        self.name = name
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.productType = productType
    }
}
