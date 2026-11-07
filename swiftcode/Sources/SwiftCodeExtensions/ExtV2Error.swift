import Foundation

public enum ExtV2Error: Error, LocalizedError, Sendable {
    case notInstalled(String)
    case disabled(String)
    case incompatible(String)
    case missingDependencies([String])
    case permissionDenied(ExtV2Capability)
    case registry(String)
    case network(String)
    case package(String)
    case manifest(String)
    case host(String)
    case timeout(String)
    case invalidRequest(String)
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id): return "Extension '\(id)' is not installed."
        case .disabled(let id): return "Extension '\(id)' is disabled."
        case .incompatible(let why): return "Incompatible extension: \(why)"
        case .missingDependencies(let ids): return "Missing dependencies: \(ids.joined(separator: ", "))"
        case .permissionDenied(let cap): return "Permission denied: \(cap.displayName). Grant it in Extensions > Permissions."
        case .registry(let m), .network(let m), .package(let m), .manifest(let m),
             .host(let m), .timeout(let m), .invalidRequest(let m), .unknown(let m):
            return m
        case .cancelled: return "Operation cancelled."
        }
    }
}
