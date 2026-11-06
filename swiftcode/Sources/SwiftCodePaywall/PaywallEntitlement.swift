import Foundation

/// Where Pro access currently comes from, so debug views can show it
/// honestly instead of a bare on/off flag.
public enum ProAccessSource: String, Equatable, Sendable {
    /// A verified current entitlement from the App Store.
    case entitlements
    /// The developer `bypass_paywall` flag (UserDefaults, same key as
    /// Legacy's `FeatureFlags.bypass_paywall`).
    case bypassFlag
    /// A debug-only override set through `PaywallStore.setDebugProAccess`
    /// — no transaction exists behind it.
    case debugOverride
    /// No Pro access from any source.
    case none
}

/// The pure entitlement state, ported from Legacy's
/// `EntitlementManager` (`SwiftCode/Backend/Store/EntitlementManager.swift`).
///
/// Legacy's rule, preserved exactly:
/// - Pro when the verified current-entitlement set is non-empty
///   (`StoreKitManager` set `isPro` from `!purchasedIDs.isEmpty`),
///   OR the `bypass_paywall` developer flag is on.
/// - `updateProStatus(isPro:)` set `isProUser = isPro || bypass`, so
///   the debug views could force the flag either way; the next real
///   entitlement refresh overwrote it from the App Store.
///
/// This type keeps that rule testable without StoreKit. Two
/// deliberate, recorded differences from Legacy's two booleans:
/// - `debugOverride` is explicit (`Bool?`, `nil` = no override)
///   instead of silently overwriting the flag, so a debug view can
///   tell a forced grant apart from a real entitlement.
/// - `source` names which input is granting access, so the debug
///   views never present a forced grant as a real purchase.
///
/// One faithful quirk to know about: Legacy granted Pro for *any*
/// verified current entitlement, not just the three catalog IDs —
/// `updateCustomerProductStatus` inserted every verified
/// transaction's product ID and tested only that the set was
/// non-empty. This port keeps that rule. If App Store Connect ever
/// gains another SwiftCode product, it also grants Pro, exactly as
/// Legacy behaved; narrowing the gate to catalog IDs would be a
/// product decision, not a port.
public struct PaywallEntitlementState: Equatable, Sendable {
    /// Product IDs with a verified current entitlement, as refreshed
    /// from `Transaction.currentEntitlements`.
    public var purchasedProductIDs: Set<String>
    /// The developer bypass flag (Legacy `FeatureFlags.bypass_paywall`).
    public var bypassPaywall: Bool
    /// Debug-only override. `nil` means no override: the flag follows
    /// entitlements and the bypass flag. Set by
    /// `PaywallStore.setDebugProAccess(_:)`; cleared by the next real
    /// entitlement refresh.
    public var debugOverride: Bool?

    public init(purchasedProductIDs: Set<String> = [], bypassPaywall: Bool = false, debugOverride: Bool? = nil) {
        self.purchasedProductIDs = purchasedProductIDs
        self.bypassPaywall = bypassPaywall
        self.debugOverride = debugOverride
    }

    /// Legacy's `isProUser` / `proAccess`: the debug override wins
    /// when set, otherwise any verified entitlement or the bypass flag.
    public var isPro: Bool {
        if let debugOverride { return debugOverride }
        return !purchasedProductIDs.isEmpty || bypassPaywall
    }

    /// Legacy's `proAccess` — identical to `isPro`.
    public var proAccess: Bool { isPro }

    /// Which input is granting access right now.
    public var source: ProAccessSource {
        if debugOverride != nil { return .debugOverride }
        if !purchasedProductIDs.isEmpty { return .entitlements }
        if bypassPaywall { return .bypassFlag }
        return .none
    }

    /// The pure form of Legacy's `updateProStatus(isPro:)`: the value
    /// the debug views force, combined with the bypass flag. Used by
    /// `PaywallStore.setDebugProAccess(_:)`; the state itself is
    /// updated through `debugOverride` so the source stays visible.
    public static func resolve(purchasedProductIDs: Set<String>, bypassPaywall: Bool, debugOverride: Bool?) -> Bool {
        PaywallEntitlementState(
            purchasedProductIDs: purchasedProductIDs,
            bypassPaywall: bypassPaywall,
            debugOverride: debugOverride
        ).isPro
    }
}
