import Foundation
import Testing
@testable import YcodePaywall

/// The catalog holds Dylan's three App Store Connect product IDs as
/// configuration, and offers are ordered cheapest-first. No prices
/// are tested here because none exist in this target: prices come
/// only from a live StoreKit fetch.
struct PaywallProductCatalogTests {

    @Test("Catalog holds exactly the three Legacy product IDs")
    func catalogIdentifiers() {
        #expect(PaywallProductCatalog.identifiers == [
            "swiftcode.pro.monthly",
            "swiftcode.pro.yearly",
            "swiftcode.pro.lifetime",
        ])
        #expect(PaywallProductCatalog.all.count == 3)
    }

    @Test("Catalog kinds match their IDs")
    func catalogKinds() {
        #expect(PaywallProductCatalog.monthly.kind == .monthly)
        #expect(PaywallProductCatalog.yearly.kind == .yearly)
        #expect(PaywallProductCatalog.lifetime.kind == .lifetime)
        #expect(PaywallProductCatalog.product(id: "swiftcode.pro.monthly")?.kind == .monthly)
        #expect(PaywallProductCatalog.product(id: "swiftcode.pro.weekly") == nil)
    }

    @Test("isKnownProduct accepts the catalog and rejects anything else")
    func knownProducts() {
        #expect(PaywallProductCatalog.isKnownProduct(id: "swiftcode.pro.monthly"))
        #expect(PaywallProductCatalog.isKnownProduct(id: "swiftcode.pro.yearly"))
        #expect(PaywallProductCatalog.isKnownProduct(id: "swiftcode.pro.lifetime"))
        #expect(!PaywallProductCatalog.isKnownProduct(id: "swiftcode.pro.weekly"))
        #expect(!PaywallProductCatalog.isKnownProduct(id: ""))
        #expect(!PaywallProductCatalog.isKnownProduct(id: "com.example.pro"))
    }

    @Test("Identifier validation accepts the catalog IDs")
    func validIdentifiers() {
        for id in PaywallProductCatalog.identifiers {
            #expect(PaywallProductCatalog.isValidIdentifier(id), "Expected \(id) to be valid")
        }
        #expect(PaywallProductCatalog.invalidIdentifiers(PaywallProductCatalog.identifiers).isEmpty)
    }

    @Test("Identifier validation rejects malformed IDs")
    func invalidIdentifiers() {
        let bad = ["", " ", "single", "a.", ".a", "a..b", "has space", "a.b_c", "a.b!"]
        for id in bad {
            #expect(!PaywallProductCatalog.isValidIdentifier(id), "Expected \(id) to be invalid")
        }
        #expect(PaywallProductCatalog.invalidIdentifiers(["swiftcode.pro.monthly", "bad id"]) == ["bad id"])
    }

    @Test("Offers sort cheapest first, as Legacy sorted fetched products")
    func offersSortedByPrice() {
        let offers = [
            PaywallProductOffer(productID: "swiftcode.pro.lifetime", displayName: "Lifetime", description: "", displayPrice: "$99.99", price: 99.99),
            PaywallProductOffer(productID: "swiftcode.pro.monthly", displayName: "Monthly", description: "", displayPrice: "$4.99", price: 4.99),
            PaywallProductOffer(productID: "swiftcode.pro.yearly", displayName: "Yearly", description: "", displayPrice: "$49.99", price: 49.99),
        ]
        let sorted = PaywallProductOffer.sortedByPrice(offers)
        #expect(sorted.map(\.productID) == [
            "swiftcode.pro.monthly",
            "swiftcode.pro.yearly",
            "swiftcode.pro.lifetime",
        ])
    }

    @Test("Paywall advertises Legacy's six Pro features verbatim")
    func proFeatures() {
        #expect(PaywallCopy.features == [
            "AI Documentation Insights",
            "Deployments (Netlify, Vercel, GitHub Pages)",
            "Advanced Debug Tools",
            "Extension Marketplace",
            "Binary Tool Integrations",
            "CI Builds",
        ])
    }
}
