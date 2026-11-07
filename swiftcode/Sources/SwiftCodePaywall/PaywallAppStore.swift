import Foundation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(StoreKit)
import StoreKit
#endif

public enum PaywallAppStore {
    public static func sync() async throws {
        #if canImport(StoreKit)
        try await StoreKit.AppStore.sync()
        #else
        throw PaywallError.storeKitUnavailable
        #endif
    }

    @MainActor
    public static func showManageSubscriptions() throws {
        #if canImport(AppKit)
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            throw PaywallError.subscriptionsUnavailable
        }
        NSWorkspace.shared.open(url)
        #else
        throw PaywallError.subscriptionsUnavailable
        #endif
    }
}
