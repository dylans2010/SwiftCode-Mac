import Foundation
import StoreKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public enum AppStore {
    public static func sync() async throws {
        try await StoreKit.AppStore.sync()
    }

    @MainActor
    public static func showManageSubscriptions() {
        #if os(iOS) || os(tvOS)
        Task {
            do {
                guard let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
                try await StoreKit.AppStore.showManageSubscriptions(in: windowScene)
            } catch {
                print("Failed to show manage subscriptions: \(error)")
            }
        }
        #else
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
