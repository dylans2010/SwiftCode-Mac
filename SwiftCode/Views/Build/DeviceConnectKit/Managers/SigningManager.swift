import Foundation
import Observation

@Observable
@MainActor
public final class SigningManager {
    public static let shared = SigningManager()

    public private(set) var signingStatus: SigningStatus = .idle
    public private(set) var availableIdentities: [String] = []

    private let service = SigningService()

    private init() {}

    public func verifySigning() async {
        signingStatus = .verifying
        do {
            let identities = try await service.validateIdentities()
            self.availableIdentities = identities
            if !identities.isEmpty {
                self.signingStatus = .valid
            } else {
                self.signingStatus = .invalid
            }
        } catch {
            self.availableIdentities = []
            self.signingStatus = .invalid
        }
    }
}
