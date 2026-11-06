import Foundation

#if canImport(AppKit)
import AppKit
#endif
#if canImport(StoreKit)
import StoreKit
#endif

/// The App Store account helpers, ported from Legacy's `AppStore`
/// enum (`SwiftCode/Backend/Store/AppStore.swift`).
///
/// `sync()` is StoreKit 2's `AppStore.sync()` — it asks the App Store
/// to re-deliver the app's purchase information (the restore path).
/// `showManageSubscriptions()` is Legacy's macOS behaviour exactly:
/// open the account subscriptions page. Legacy's iOS branch (present
/// the system manage-subscriptions sheet in a window scene) is not
/// ported: a library target has no window scene to present from, and
/// this IDE ships on macOS.
public enum PaywallAppStore {
    /// Synchronizes the app's purchase information with the App Store.
    /// Throws `PaywallError.storeKitUnavailable` where StoreKit does
    /// not exist instead of pretending the sync happened.
    public static func sync() async throws {
        #if canImport(StoreKit)
        try await StoreKit.AppStore.sync()
        #else
        throw PaywallError.storeKitUnavailable
        #endif
    }

    /// Opens the App Store account subscriptions page, as Legacy did
    /// on macOS. Throws `PaywallError.subscriptionsUnavailable` where
    /// there is no AppKit workspace to open it with.
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
