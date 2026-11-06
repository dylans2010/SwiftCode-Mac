import Foundation

/// The SwiftCode Pro product catalog, ported from Legacy's
/// `StoreKitManager.productIdentifiers`
/// (`SwiftCode/Backend/Store/StoreKitManager.swift`).
///
/// The three identifiers below are configuration, not code: they are
/// Dylan's App Store Connect product IDs. The products themselves are
/// never invented here — `PaywallStore.loadProducts()` fetches them
/// live from the App Store with StoreKit 2
/// (`Product.products(for:)`), and prices come only from that live
/// fetch (`displayPrice` on the returned product). There are no
/// hardcoded prices anywhere in this target: if App Store Connect has
/// no matching product, the fetch returns nothing and the paywall
/// shows its loading/empty state instead of a made-up price.
///
/// Do not add a product ID here without the matching product existing
/// in App Store Connect, and do not depend on `frameworks/storekit`'s
/// `StoreKit` product from this target: that module re-implements the
/// StoreKit API under the same module name, and depending on it would
/// shadow Apple's real `StoreKit` framework this target calls.
public struct PaywallProduct: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: Kind

    public enum Kind: String, Sendable, CaseIterable {
        case monthly
        case yearly
        case lifetime
    }

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public enum PaywallProductCatalog {
    /// Auto-renewable monthly subscription.
    public static let monthly = PaywallProduct(id: "swiftcode.pro.monthly", kind: .monthly)
    /// Auto-renewable yearly subscription.
    public static let yearly = PaywallProduct(id: "swiftcode.pro.yearly", kind: .yearly)
    /// One-time lifetime purchase.
    public static let lifetime = PaywallProduct(id: "swiftcode.pro.lifetime", kind: .lifetime)

    /// All products, in the order Legacy fetched them.
    public static let all: [PaywallProduct] = [monthly, yearly, lifetime]

    /// The identifier list handed to StoreKit's live product fetch.
    public static var identifiers: [String] { all.map(\.id) }

    /// Whether an identifier is one of the three catalog products.
    public static func isKnownProduct(id: String) -> Bool {
        all.contains { $0.id == id }
    }

    /// The product for an identifier, or `nil` when it is not in the catalog.
    public static func product(id: String) -> PaywallProduct? {
        all.first { $0.id == id }
    }

    /// Validates product identifiers the way App Store Connect product
    /// IDs are shaped: non-empty, no whitespace, at least two
    /// dot-separated labels of letters, digits, or hyphens. Returns
    /// the identifiers that fail, so a bad configuration is reported
    /// instead of silently fetching nothing.
    public static func invalidIdentifiers(_ identifiers: [String]) -> [String] {
        identifiers.filter { !isValidIdentifier($0) }
    }

    public static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, !identifier.contains(where: { $0.isWhitespace }) else { return false }
        let labels = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

/// A product offer for the paywall UI, built only from a live StoreKit
/// `Product` by `PaywallStore`. `displayPrice` is the App Store's
/// localized price string for that product; `price` is the same price
/// as a number, used only to order offers cheapest-first (Legacy
/// sorted `products` by `price`). Neither is ever set from a constant:
/// an offer with no live product behind it cannot exist.
public struct PaywallProductOffer: Identifiable, Hashable, Sendable {
    public let productID: String
    public let displayName: String
    public let description: String
    public let displayPrice: String
    public let price: Double

    public var id: String { productID }

    public init(productID: String, displayName: String, description: String, displayPrice: String, price: Double) {
        self.productID = productID
        self.displayName = displayName
        self.description = description
        self.displayPrice = displayPrice
        self.price = price
    }

    /// Cheapest first, exactly as Legacy sorted its fetched products.
    public static func sortedByPrice(_ offers: [PaywallProductOffer]) -> [PaywallProductOffer] {
        offers.sorted { $0.price < $1.price }
    }
}

/// The Pro feature list the paywall advertises, copied verbatim from
/// Legacy's `PaywallView.features`. This is marketing copy for the
/// paywall UI, kept in the runtime (not the view) so tests can check
/// it without a window. It is a list of promises, not a gate: the
/// only gate in this target is `PaywallEntitlementState.isPro`.
public enum PaywallCopy {
    public static let features: [String] = [
        "AI Documentation Insights",
        "Deployments (Netlify, Vercel, GitHub Pages)",
        "Advanced Debug Tools",
        "Extension Marketplace",
        "Binary Tool Integrations",
        "CI Builds",
    ]
}
