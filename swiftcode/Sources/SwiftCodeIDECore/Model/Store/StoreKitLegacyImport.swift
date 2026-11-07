import Foundation
import StoreKitConfiguration

public struct StoreKitLegacyImportReport: Sendable {
    public var notes: [String]
    public var droppedAnything: Bool { !notes.isEmpty }

    public init(notes: [String] = []) { self.notes = notes }
}

public enum StoreKitLegacyImport {

    struct LegacyLocalization: Decodable {
        var locale: String
        var displayName: String
        var description: String
    }

    struct LegacySettings: Decodable {
        var billingGracePeriodEnabled: Bool?
        var billingRetryEnabled: Bool?
        var failTransactionsEnabled: Bool?
        var storeKitError: String?
        var locale: String?
        var storefront: String?
        var timeRate: String?
    }

    struct LegacyIntroOffer: Decodable {
        var numberOfPeriods: Int?
        var paymentMode: String?
        var price: Double?
        var subscriptionPeriod: String?
    }

    struct LegacyPromoOffer: Decodable {
        var offerID: String?
        var referenceName: String?
        var paymentMode: String?
        var price: Double?
        var numberOfPeriods: Int?
        var subscriptionPeriod: String?
    }

    struct LegacyOfferCode: Decodable {
        var code: String?
        var referenceName: String?
        var customerEligibility: String?
        var expirationDate: String?
    }

    struct LegacyProduct: Decodable {
        var productID: String
        var referenceName: String
        var type: String?
        var localizations: [LegacyLocalization]?
        var price: Double?
        var familySharing: Bool?
        var subscriptionGroupID: String?
        var subscriptionPeriod: String?
        var introductoryOffers: [LegacyIntroOffer]?
        var promotionalOffers: [LegacyPromoOffer]?
        var winBackOffers: [LegacyPromoOffer]?
        var offerCodes: [LegacyOfferCode]?
    }

    struct LegacyGroup: Decodable {
        var id: String?
        var referenceName: String?
        var localizations: [LegacyLocalization]?
        var subscriptions: [LegacyProduct]?
    }

    struct LegacyConfig: Decodable {
        var identifier: String?
        var settings: LegacySettings?
        var products: [LegacyProduct]?
        var subscriptionGroups: [LegacyGroup]?
        var nonRenewingSubscriptions: [LegacyProduct]?
        var version: [Int]?
    }

    public static func importConfiguration(data: Data) throws -> (StoreConfiguration, StoreKitLegacyImportReport) {
        let legacy = try JSONDecoder().decode(LegacyConfig.self, from: data)
        return importConfiguration(legacy)
    }

    static func importConfiguration(_ legacy: LegacyConfig) -> (StoreConfiguration, StoreKitLegacyImportReport) {
        var notes: [String] = []
        var nextID = 1
        func freshID() -> String { defer { nextID += 1 }; return String(nextID) }

        func price(_ value: Double?) -> String? {
            guard let value else { return nil }
            return String(format: "%.2f", value)
        }

        func localizations(_ list: [LegacyLocalization]?) -> [Localization]? {
            list?.map { Localization(locale: $0.locale, displayName: $0.displayName, description: $0.description) }
        }

        func paymentMode(_ raw: String?) -> PaymentMode? {
            guard let raw else { return nil }
            if raw == "freeTrial" { return .free }
            return PaymentMode(rawValue: raw)
        }

        func offers(_ product: LegacyProduct) -> (intro: Offer?, adHoc: [Offer]?, codes: [Offer]?, winback: [JSONValue]?) {
            var intro: Offer?
            if let first = product.introductoryOffers?.first {
                intro = Offer(internalID: freshID(), paymentMode: paymentMode(first.paymentMode),
                              subscriptionPeriod: first.subscriptionPeriod, numberOfPeriods: first.numberOfPeriods,
                              displayPrice: price(first.price))
                if first.paymentMode == "freeTrial" {
                    notes.append("Product '\(product.productID)': introductory offer payment mode 'freeTrial' was mapped to the format's 'free'.")
                }
                if (product.introductoryOffers?.count ?? 0) > 1 {
                    notes.append("Product '\(product.productID)': only the first introductory offer was kept; the format has one introductoryOffer.")
                }
            }
            let adHoc: [Offer]? = product.promotionalOffers?.map { o in
                Offer(internalID: freshID(), offerID: o.offerID, referenceName: o.referenceName,
                      paymentMode: paymentMode(o.paymentMode),
                      subscriptionPeriod: o.subscriptionPeriod, numberOfPeriods: o.numberOfPeriods,
                      displayPrice: price(o.price))
            }
            let codes: [Offer]? = product.offerCodes?.map { o in
                if o.expirationDate != nil {
                    notes.append("Product '\(product.productID)': offer code '\(o.code ?? "")' had an expiration date, which the .storekit format does not carry; it was dropped.")
                }
                let eligibility: [String]?
                switch o.customerEligibility {
                case "new": eligibility = ["new"]
                case "existing": eligibility = ["existing"]
                case "all": eligibility = ["new", "existing", "expired"]
                case nil: eligibility = nil
                default: eligibility = nil
                }
                return Offer(internalID: freshID(), referenceName: o.code,
                             paymentMode: .payAsYouGo, subscriptionPeriod: "P1M", numberOfPeriods: 1,
                             displayPrice: "0.00", eligibility: eligibility)
            }
            if let winBack = product.winBackOffers, !winBack.isEmpty {
                notes.append("Product '\(product.productID)': \(winBack.count) win-back offer(s) were dropped; Legacy's win-back shape has no .storekit equivalent.")
            }
            return (intro, adHoc, codes, nil)
        }

        func convertProduct(_ p: LegacyProduct, groupID: String? = nil, groupNumber: Int? = nil) -> ConfiguredProduct {
            let (intro, adHoc, codes, _) = offers(p)
            let type: ProductKind?
            switch p.type {
            case "Consumable": type = .consumable
            case "NonConsumable": type = .nonConsumable
            case "NonRenewingSubscription": type = .nonRenewingSubscription
            case "AutoRenewableSubscription", "RecurringSubscription": type = .recurringSubscription
            case nil: type = nil
            default: type = ProductKind(rawValue: p.type!)
            }
            return ConfiguredProduct(
                type: type, productID: p.productID, referenceName: p.referenceName,
                internalID: freshID(), displayPrice: price(p.price),
                familyShareable: p.familySharing, localizations: localizations(p.localizations),
                subscriptionGroupID: groupID ?? p.subscriptionGroupID, groupNumber: groupNumber,
                recurringSubscriptionPeriod: p.subscriptionPeriod,
                introductoryOffer: intro, adHocOffers: adHoc, codeOffers: codes)
        }

        var groups: [SubscriptionGroup] = []
        for g in legacy.subscriptionGroups ?? [] {
            let id = freshID()
            if let gid = g.id, !gid.allSatisfy({ $0.isNumber }) {
                notes.append("Group '\(g.referenceName ?? gid)': Legacy's group id '\(gid)' is not a digit string and was replaced with '\(id)'.")
            }
            var subscriptions: [ConfiguredProduct] = []
            for (i, s) in (g.subscriptions ?? []).enumerated() {
                subscriptions.append(convertProduct(s, groupID: id, groupNumber: i + 1))
            }
            groups.append(SubscriptionGroup(id: id, name: g.referenceName,
                                            localizations: localizations(g.localizations),
                                            subscriptions: subscriptions))
        }
        let products = (legacy.products ?? []).map { convertProduct($0) }
        let nonRenewing = (legacy.nonRenewingSubscriptions ?? []).map { convertProduct($0) }

        var settings: Settings?
        if let s = legacy.settings {
            var mapped = Settings(storefront: s.storefront, locale: s.locale)
            mapped.billingGracePeriodEnabled = s.billingGracePeriodEnabled
            mapped.renewalBillingIssuesEnabled = s.billingRetryEnabled
            mapped.failTransactionsEnabled = s.failTransactionsEnabled
            if let error = s.storeKitError {
                notes.append("Settings: the Legacy storeKitError '\(error)' has no .storekit equivalent and was dropped.")
            }
            if let rate = s.timeRate, rate != "none" {
                notes.append("Settings: the Legacy time rate '\(rate)' has no .storekit equivalent and was dropped; the time rate is unset.")
            }
            settings = mapped
        }

        var version: Version?
        if let v = legacy.version {
            version = Version(major: v.first, minor: v.count > 1 ? v[1] : nil)
        }

        notes.append("Import note: Legacy ordering (index), availability and product images have no .storekit equivalent and were not carried over.")
        notes.append("Import note: every product and offer was given a fresh numeric internal ID; Legacy files carry none.")

        let config = StoreConfiguration(
            identifier: legacy.identifier, version: version,
            products: products.isEmpty ? nil : products,
            nonRenewingSubscriptions: nonRenewing.isEmpty ? nil : nonRenewing,
            subscriptionGroups: groups.isEmpty ? nil : groups,
            settings: settings)
        return (config, StoreKitLegacyImportReport(notes: notes))
    }
}
