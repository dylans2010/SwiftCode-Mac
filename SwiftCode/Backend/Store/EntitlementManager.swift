import Foundation
import Combine

final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()

    @Published private(set) var isProUser: Bool = false

    private init() {
        // Initial state will be updated by StoreKitManager
    }

    func updateProStatus(isPro: Bool) {
        DispatchQueue.main.async {
            self.isProUser = isPro || FeatureFlags.shared.bypass_paywall
        }
    }

    var proAccess: Bool {
        isProUser || FeatureFlags.shared.bypass_paywall
    }
}
