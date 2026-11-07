import Foundation

public enum CloudError: Error, LocalizedError, Sendable, Equatable {
    case unauthenticated
    case missingSwiftCodeID
    case networkError(String)
    case databaseError(String)
    case storageError(String)
    case syncFailed(String)
    case conflictDetected(String)
    case offline

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "User is not authenticated. Please sign in to access cloud services."
        case .missingSwiftCodeID:
            return "No valid permanent SwiftCode ID found. Access is restricted."
        case .networkError(let details):
            return "Cloud network failure: \(details)"
        case .databaseError(let details):
            return "Cloud database operation failed: \(details)"
        case .storageError(let details):
            return "Cloud storage operation failed: \(details)"
        case .syncFailed(let details):
            return "Cloud synchronization failed: \(details)"
        case .conflictDetected(let details):
            return "A synchronization conflict was detected: \(details)"
        case .offline:
            return "The device is currently offline. Changes will sync once connection is restored."
        }
    }
}
