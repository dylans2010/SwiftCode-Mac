import Foundation

public enum ProAccessSource: String, Equatable, Sendable {
    case entitlements
    case bypassFlag
    case debugOverride
    case none
}

public struct PaywallEntitlementState: Equatable, Sendable {
    public var purchasedProductIDs: Set<String>
    public var bypassPaywall: Bool
    public var debugOverride: Bool?

    public init(purchasedProductIDs: Set<String> = [], bypassPaywall: Bool = false, debugOverride: Bool? = nil) {
        self.purchasedProductIDs = purchasedProductIDs
        self.bypassPaywall = bypassPaywall
        self.debugOverride = debugOverride
    }

    public var isPro: Bool {
        if let debugOverride { return debugOverride }
        return !purchasedProductIDs.isEmpty || bypassPaywall
    }

    public var proAccess: Bool { isPro }

    public var source: ProAccessSource {
        if debugOverride != nil { return .debugOverride }
        if !purchasedProductIDs.isEmpty { return .entitlements }
        if bypassPaywall { return .bypassFlag }
        return .none
    }

    public static func resolve(purchasedProductIDs: Set<String>, bypassPaywall: Bool, debugOverride: Bool?) -> Bool {
        PaywallEntitlementState(
            purchasedProductIDs: purchasedProductIDs,
            bypassPaywall: bypassPaywall,
            debugOverride: debugOverride
        ).isPro
    }
}
