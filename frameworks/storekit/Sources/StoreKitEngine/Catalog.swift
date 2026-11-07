import Foundation
import StoreKitConfiguration

public enum ProductType: String, Codable, Sendable, CaseIterable {
    case consumable = "Consumable"
    case nonConsumable = "Non-Consumable"
    case nonRenewable = "Non-Renewing Subscription"
    case autoRenewable = "Auto-Renewable Subscription"

    init?(kind: ProductKind?) {
        switch kind {
        case .consumable?: self = .consumable
        case .nonConsumable?: self = .nonConsumable
        case .nonRenewingSubscription?: self = .nonRenewable
        case .recurringSubscription?: self = .autoRenewable
        default: return nil
        }
    }
}

public enum OfferPaymentMode: String, Codable, Sendable, CaseIterable {
    case freeTrial = "FREE_TRIAL"
    case payAsYouGo = "PAY_AS_YOU_GO"
    case payUpFront = "PAY_UP_FRONT"

    init?(_ mode: PaymentMode?) {
        switch mode {
        case .free?: self = .freeTrial
        case .payAsYouGo?: self = .payAsYouGo
        case .payUpFront?: self = .payUpFront
        default: return nil
        }
    }

    public var productJSONMode: String {
        switch self {
        case .freeTrial: return "FreeTrial"
        case .payAsYouGo: return "PayAsYouGo"
        case .payUpFront: return "PayUpFront"
        }
    }
}

public enum OfferType: Int, Codable, Sendable, CaseIterable {
    case introductory = 1
    case promotional = 2
    case code = 3
    case winBack = 4
}

public struct CatalogLocalization: Hashable, Sendable, Codable {
    public let locale: String
    public let displayName: String
    public let description: String
}

public struct CatalogOffer: Hashable, Sendable {
    public let type: OfferType
    public let identifier: String?
    public let internalID: String
    public let paymentMode: OfferPaymentMode
    public let period: SubscriptionDuration
    public let periodCount: Int
    public let price: Decimal
    public let priceText: String
    public let eligibility: Set<String>
    public let isStackable: Bool

    public var totalDuration: SubscriptionDuration { period.times(periodCount) }
}

public struct CatalogSubscription: Hashable, Sendable {
    public let groupID: String
    public let level: Int
    public let period: SubscriptionDuration
    public let introductoryOffer: CatalogOffer?
    public let promotionalOffers: [CatalogOffer]
    public let codeOffers: [CatalogOffer]
}

public struct CatalogProduct: Hashable, Sendable {
    public let id: String
    public let internalID: String
    public let type: ProductType
    public let referenceName: String
    public let price: Decimal
    public let priceText: String
    public let isFamilyShareable: Bool
    public let localizations: [CatalogLocalization]
    public let subscription: CatalogSubscription?

    public var priceMilli: Int { milliUnits(price) }

    public func displayName(locale: String) -> String { localization(for: locale)?.displayName ?? referenceName }

    public func description(locale: String) -> String? { localization(for: locale)?.description }

    public func localization(for locale: String) -> CatalogLocalization? {
        let wanted = normalizedLocale(locale)
        return localizations.first { normalizedLocale($0.locale) == wanted }
    }
}

public struct CatalogGroup: Hashable, Sendable {
    public let id: String
    public let name: String
    public let localizations: [CatalogLocalization]
    public let productIDs: [String]

    public func displayName(locale: String) -> String {
        let wanted = normalizedLocale(locale)
        return localizations.first { normalizedLocale($0.locale) == wanted }?.displayName ?? name
    }
}

func normalizedLocale(_ s: String) -> String { s.replacingOccurrences(of: "-", with: "_") }

func milliUnits(_ price: Decimal) -> Int {
    var scaled = price * 1000
    var rounded = Decimal()
    NSDecimalRound(&rounded, &scaled, 0, .plain)
    return NSDecimalNumber(decimal: rounded).intValue
}

func parsePrice(_ text: String?) -> (Decimal, String) {
    guard let text, isDecimalPrice(text), let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
        return (0, "0")
    }
    return (d, text)
}

public struct Catalog: Hashable, Sendable {
    public let products: [CatalogProduct]
    public let groups: [CatalogGroup]

    public init(_ configuration: StoreConfiguration) {
        var products: [CatalogProduct] = []
        var seen: Set<String> = []
        func localizations(_ list: [Localization]?) -> [CatalogLocalization] {
            (list ?? []).compactMap { l in
                guard let locale = l.locale else { return nil }
                return CatalogLocalization(locale: locale, displayName: l.displayName ?? "", description: l.description ?? "")
            }
        }
        func offer(_ o: Offer, type: OfferType, identifier: String?) -> CatalogOffer? {
            guard let mode = OfferPaymentMode(o.paymentMode),
                  let period = o.subscriptionPeriod.flatMap(SubscriptionDuration.init(iso8601:)) else { return nil }
            let (price, text) = mode == .freeTrial ? (Decimal(0), "0") : parsePrice(o.displayPrice)
            return CatalogOffer(
                type: type, identifier: identifier, internalID: o.internalID ?? "", paymentMode: mode, period: period,
                periodCount: max(1, o.numberOfPeriods ?? 1), price: price, priceText: text,
                eligibility: Set(o.eligibility ?? []), isStackable: o.isStackable ?? false)
        }
        func make(_ p: ConfiguredProduct, group: SubscriptionGroup?) -> CatalogProduct? {
            guard let id = p.productID, !id.isEmpty, !seen.contains(id), let type = ProductType(kind: p.type) else { return nil }
            var subscription: CatalogSubscription?
            if type == .autoRenewable {
                guard let group, let gid = group.id,
                      let period = p.recurringSubscriptionPeriod.flatMap(SubscriptionDuration.init(iso8601:)) else { return nil }
                subscription = CatalogSubscription(
                    groupID: gid, level: max(1, p.groupNumber ?? 1), period: period,
                    introductoryOffer: p.introductoryOffer.flatMap { offer($0, type: .introductory, identifier: nil) },
                    promotionalOffers: (p.adHocOffers ?? []).compactMap { o in
                        guard let oid = o.offerID, !oid.isEmpty else { return nil }
                        return offer(o, type: .promotional, identifier: oid)
                    },
                    codeOffers: (p.codeOffers ?? []).compactMap { o in
                        guard let code = o.referenceName, !code.isEmpty else { return nil }
                        return offer(o, type: .code, identifier: code)
                    })
            } else if group != nil {
                return nil
            }
            seen.insert(id)
            let (price, text) = parsePrice(p.displayPrice)
            return CatalogProduct(
                id: id, internalID: p.internalID ?? "", type: type, referenceName: p.referenceName ?? id, price: price,
                priceText: text, isFamilyShareable: p.familyShareable ?? false,
                localizations: localizations(p.localizations), subscription: subscription)
        }
        for p in configuration.products ?? [] where p.type == .consumable || p.type == .nonConsumable {
            if let made = make(p, group: nil) { products.append(made) }
        }
        for p in configuration.nonRenewingSubscriptions ?? [] where p.type == .nonRenewingSubscription {
            if let made = make(p, group: nil) { products.append(made) }
        }
        var groups: [CatalogGroup] = []
        for g in configuration.subscriptionGroups ?? [] {
            guard let gid = g.id, !groups.contains(where: { $0.id == gid }) else { continue }
            var ids: [String] = []
            for s in g.subscriptions ?? [] where s.type == .recurringSubscription {
                if let made = make(s, group: g) { products.append(made); ids.append(made.id) }
            }
            groups.append(CatalogGroup(id: gid, name: g.name ?? "", localizations: localizations(g.localizations), productIDs: ids))
        }
        self.products = products
        self.groups = groups
    }

    public func product(_ id: String) -> CatalogProduct? { products.first { $0.id == id } }

    public func group(_ id: String) -> CatalogGroup? { groups.first { $0.id == id } }
}

public struct Storefront: Hashable, Sendable, Codable {
    public let countryCode: String
    public let id: String
    public let currency: String

    public static let known: [Storefront] = [
        ("USA", "143441", "USD"), ("FRA", "143442", "EUR"), ("DEU", "143443", "EUR"), ("GBR", "143444", "GBP"),
        ("AUT", "143445", "EUR"), ("BEL", "143446", "EUR"), ("FIN", "143447", "EUR"), ("GRC", "143448", "EUR"),
        ("IRL", "143449", "EUR"), ("ITA", "143450", "EUR"), ("LUX", "143451", "EUR"), ("NLD", "143452", "EUR"),
        ("PRT", "143453", "EUR"), ("ESP", "143454", "EUR"), ("CAN", "143455", "CAD"), ("SWE", "143456", "SEK"),
        ("NOR", "143457", "NOK"), ("DNK", "143458", "DKK"), ("CHE", "143459", "CHF"), ("AUS", "143460", "AUD"),
        ("NZL", "143461", "NZD"), ("JPN", "143462", "JPY"), ("HKG", "143463", "HKD"), ("SGP", "143464", "SGD"),
        ("CHN", "143465", "CNY"), ("KOR", "143466", "KRW"), ("IND", "143467", "INR"), ("MEX", "143468", "MXN"),
        ("BRA", "143503", "BRL"),
    ].map { Storefront(countryCode: $0.0, id: $0.1, currency: $0.2) }

    public static func named(_ countryCode: String) -> Storefront {
        known.first { $0.countryCode == countryCode } ?? Storefront(countryCode: countryCode, id: "", currency: "XXX")
    }

    public func priceLocaleIdentifier(locale: String) -> String { "\(locale)@currency=\(currency)" }
}

public enum PriceFormatter {
    public static func displayPrice(_ price: Decimal, priceLocale: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: priceLocale)
        f.numberStyle = .currency
        if let code = currencyCode(priceLocale) { f.currencyCode = code }
        return f.string(from: NSDecimalNumber(decimal: price)) ?? "\(price)"
    }

    public static func plainPrice(_ price: Decimal, currency: String) -> String {
        let digits = ["JPY", "KRW", "CLP", "VND", "ISK", "HUF", "TWD"].contains(currency) ? 0 : 2
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.minimumIntegerDigits = 1
        return f.string(from: NSDecimalNumber(decimal: price)) ?? "\(price)"
    }

    static func currencyCode(_ priceLocale: String) -> String? {
        guard let range = priceLocale.range(of: "@currency=") else { return nil }
        return String(priceLocale[range.upperBound...].prefix(3))
    }
}
