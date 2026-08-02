import Foundation

public enum SigningStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Unverified"
    case verifying = "Verifying"
    case valid = "Valid Signing"
    case invalid = "Invalid Profile/Certificate"
    case expired = "Expired Provisioning"

    public var description: String {
        return self.rawValue
    }
}
