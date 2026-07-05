import Foundation
import StoreKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
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
        #if canImport(AppKit)
        Task {
            do {
                guard let window = NSApplication.shared.mainWindow else { return }
                try await StoreKit.AppStore.showManageSubscriptions(in: window)
            } catch {
                print("Failed to show manage subscriptions: \(error)")
            }
        }
        #endif
    }
}
