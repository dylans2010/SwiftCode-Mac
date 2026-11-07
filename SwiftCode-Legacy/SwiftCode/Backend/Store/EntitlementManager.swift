import Foundation
import Combine

final class EntitlementManager: ObservableObject, @unchecked Sendable {
    static let shared = EntitlementManager()

    @Published private(set) var isProUser: Bool = false

    private init() {
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
