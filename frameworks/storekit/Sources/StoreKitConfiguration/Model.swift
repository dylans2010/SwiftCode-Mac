public struct StoreConfiguration: Hashable, Sendable {
    public var identifier: String?
    public var version: Version?
    public var products: [ConfiguredProduct]?
    public var nonRenewingSubscriptions: [ConfiguredProduct]?
    public var subscriptionGroups: [SubscriptionGroup]?
    public var settings: Settings?
    public var appPolicies: AppPolicies?
    public var appName: String?
    public var extra: [String: JSONValue]

    public init(
        identifier: String? = nil, version: Version? = nil, products: [ConfiguredProduct]? = nil,
        nonRenewingSubscriptions: [ConfiguredProduct]? = nil, subscriptionGroups: [SubscriptionGroup]? = nil,
        settings: Settings? = nil, appPolicies: AppPolicies? = nil, appName: String? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.identifier = identifier
        self.version = version
        self.products = products
        self.nonRenewingSubscriptions = nonRenewingSubscriptions
        self.subscriptionGroups = subscriptionGroups
        self.settings = settings
        self.appPolicies = appPolicies
        self.appName = appName
        self.extra = extra
    }

    public static let synchronizationKeys = ["_applicationInternalID", "_developerTeamID", "_lastSynchronizedDate"]

    public var isSynchronized: Bool { StoreConfiguration.synchronizationKeys.contains { extra[$0] != nil } }

    public var allProducts: [ConfiguredProduct] {
        (products ?? []) + (nonRenewingSubscriptions ?? []) + (subscriptionGroups ?? []).flatMap { $0.subscriptions ?? [] }
    }
}

public struct Version: Hashable, Sendable {
    public var major: Int?
    public var minor: Int?
    public var extra: [String: JSONValue]

    public init(major: Int? = nil, minor: Int? = nil, extra: [String: JSONValue] = [:]) {
        self.major = major
        self.minor = minor
        self.extra = extra
    }
}

public struct ProductKind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let consumable = ProductKind(rawValue: "Consumable")
    public static let nonConsumable = ProductKind(rawValue: "NonConsumable")
    public static let nonRenewingSubscription = ProductKind(rawValue: "NonRenewingSubscription")
    public static let recurringSubscription = ProductKind(rawValue: "RecurringSubscription")

    public var description: String { rawValue }
}

public struct ConfiguredProduct: Hashable, Sendable {
    public var type: ProductKind?
    public var productID: String?
    public var referenceName: String?
    public var internalID: String?
    public var displayPrice: String?
    public var familyShareable: Bool?
    public var localizations: [Localization]?
    public var subscriptionGroupID: String?
    public var groupNumber: Int?
    public var recurringSubscriptionPeriod: String?
    public var introductoryOffer: Offer?
    public var adHocOffers: [Offer]?
    public var codeOffers: [Offer]?
    public var winbackOffers: [JSONValue]?
    public var extra: [String: JSONValue]

    public init(
        type: ProductKind? = nil, productID: String? = nil, referenceName: String? = nil, internalID: String? = nil,
        displayPrice: String? = nil, familyShareable: Bool? = nil, localizations: [Localization]? = nil,
        subscriptionGroupID: String? = nil, groupNumber: Int? = nil, recurringSubscriptionPeriod: String? = nil,
        introductoryOffer: Offer? = nil, adHocOffers: [Offer]? = nil, codeOffers: [Offer]? = nil,
        winbackOffers: [JSONValue]? = nil, extra: [String: JSONValue] = [:]
    ) {
        self.type = type
        self.productID = productID
        self.referenceName = referenceName
        self.internalID = internalID
        self.displayPrice = displayPrice
        self.familyShareable = familyShareable
        self.localizations = localizations
        self.subscriptionGroupID = subscriptionGroupID
        self.groupNumber = groupNumber
        self.recurringSubscriptionPeriod = recurringSubscriptionPeriod
        self.introductoryOffer = introductoryOffer
        self.adHocOffers = adHocOffers
        self.codeOffers = codeOffers
        self.winbackOffers = winbackOffers
        self.extra = extra
    }
}

public struct Localization: Hashable, Sendable {
    public var locale: String?
    public var displayName: String?
    public var description: String?
    public var extra: [String: JSONValue]

    public init(locale: String? = nil, displayName: String? = nil, description: String? = nil, extra: [String: JSONValue] = [:]) {
        self.locale = locale
        self.displayName = displayName
        self.description = description
        self.extra = extra
    }
}

public struct SubscriptionGroup: Hashable, Sendable {
    public var id: String?
    public var name: String?
    public var localizations: [Localization]?
    public var subscriptions: [ConfiguredProduct]?
    public var extra: [String: JSONValue]

    public init(
        id: String? = nil, name: String? = nil, localizations: [Localization]? = nil, subscriptions: [ConfiguredProduct]? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.localizations = localizations
        self.subscriptions = subscriptions
        self.extra = extra
    }
}

public struct PaymentMode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let free = PaymentMode(rawValue: "free")
    public static let payAsYouGo = PaymentMode(rawValue: "payAsYouGo")
    public static let payUpFront = PaymentMode(rawValue: "payUpFront")

    public var description: String { rawValue }
}

public struct Offer: Hashable, Sendable {
    public var internalID: String?
    public var offerID: String?
    public var referenceName: String?
    public var paymentMode: PaymentMode?
    public var subscriptionPeriod: String?
    public var numberOfPeriods: Int?
    public var displayPrice: String?
    public var eligibility: [String]?
    public var isStackable: Bool?
    public var extra: [String: JSONValue]

    public init(
        internalID: String? = nil, offerID: String? = nil, referenceName: String? = nil, paymentMode: PaymentMode? = nil,
        subscriptionPeriod: String? = nil, numberOfPeriods: Int? = nil, displayPrice: String? = nil,
        eligibility: [String]? = nil, isStackable: Bool? = nil, extra: [String: JSONValue] = [:]
    ) {
        self.internalID = internalID
        self.offerID = offerID
        self.referenceName = referenceName
        self.paymentMode = paymentMode
        self.subscriptionPeriod = subscriptionPeriod
        self.numberOfPeriods = numberOfPeriods
        self.displayPrice = displayPrice
        self.eligibility = eligibility
        self.isStackable = isStackable
        self.extra = extra
    }
}

public struct Settings: Hashable, Sendable {
    public var storefront: String?
    public var locale: String?
    public var timeRate: Int?
    public var askToBuyEnabled: Bool?
    public var billingIssuesEnabled: Bool?
    public var renewalBillingIssuesEnabled: Bool?
    public var billingGracePeriodEnabled: Bool?
    public var disableDialogs: Bool?
    public var failTransactionsEnabled: Bool?
    public var storeKitErrors: [JSONValue]?
    public var extra: [String: JSONValue]

    public init(
        storefront: String? = nil, locale: String? = nil, timeRate: Int? = nil, askToBuyEnabled: Bool? = nil,
        billingIssuesEnabled: Bool? = nil, renewalBillingIssuesEnabled: Bool? = nil,
        billingGracePeriodEnabled: Bool? = nil, disableDialogs: Bool? = nil, failTransactionsEnabled: Bool? = nil,
        storeKitErrors: [JSONValue]? = nil, extra: [String: JSONValue] = [:]
    ) {
        self.storefront = storefront
        self.locale = locale
        self.timeRate = timeRate
        self.askToBuyEnabled = askToBuyEnabled
        self.billingIssuesEnabled = billingIssuesEnabled
        self.renewalBillingIssuesEnabled = renewalBillingIssuesEnabled
        self.billingGracePeriodEnabled = billingGracePeriodEnabled
        self.disableDialogs = disableDialogs
        self.failTransactionsEnabled = failTransactionsEnabled
        self.storeKitErrors = storeKitErrors
        self.extra = extra
    }

    public static let defaults = Settings(
        storefront: "USA", locale: "en_US", timeRate: 0, askToBuyEnabled: false, billingIssuesEnabled: false,
        renewalBillingIssuesEnabled: false, billingGracePeriodEnabled: false, disableDialogs: false,
        failTransactionsEnabled: false, storeKitErrors: [])
}

public struct AppPolicies: Hashable, Sendable {
    public var eula: String?
    public var policies: [Policy]?
    public var extra: [String: JSONValue]

    public init(eula: String? = nil, policies: [Policy]? = nil, extra: [String: JSONValue] = [:]) {
        self.eula = eula
        self.policies = policies
        self.extra = extra
    }
}

public struct Policy: Hashable, Sendable {
    public var locale: String?
    public var policyText: String?
    public var policyURL: String?
    public var extra: [String: JSONValue]

    public init(locale: String? = nil, policyText: String? = nil, policyURL: String? = nil, extra: [String: JSONValue] = [:]) {
        self.locale = locale
        self.policyText = policyText
        self.policyURL = policyURL
        self.extra = extra
    }
}
