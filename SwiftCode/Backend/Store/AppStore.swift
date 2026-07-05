import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// A stub for AppStore functionality to resolve naming or availability conflicts.
public enum AppStore {
    /// Synchronizes the app's purchase information with the App Store.
    public static func sync() async throws {
        try await StoreKit.AppStore.sync()
    }

    /// Shows the manage subscriptions sheet.
    @MainActor
    public static func showManageSubscriptions() {
        #if canImport(UIKit)
        Task {
            do {
                guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                try await StoreKit.AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                print("Failed to show manage subscriptions: \(error)")
            }
        }
        #endif
    }
}
