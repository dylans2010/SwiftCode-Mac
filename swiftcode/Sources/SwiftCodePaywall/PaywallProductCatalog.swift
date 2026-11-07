import Foundation

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
    public static let monthly = PaywallProduct(id: "swiftcode.pro.monthly", kind: .monthly)
    public static let yearly = PaywallProduct(id: "swiftcode.pro.yearly", kind: .yearly)
    public static let lifetime = PaywallProduct(id: "swiftcode.pro.lifetime", kind: .lifetime)

    public static let all: [PaywallProduct] = [monthly, yearly, lifetime]

    public static var identifiers: [String] { all.map(\.id) }

    public static func isKnownProduct(id: String) -> Bool {
        all.contains { $0.id == id }
    }

    public static func product(id: String) -> PaywallProduct? {
        all.first { $0.id == id }
    }

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

    public static func sortedByPrice(_ offers: [PaywallProductOffer]) -> [PaywallProductOffer] {
        offers.sorted { $0.price < $1.price }
    }
}

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
