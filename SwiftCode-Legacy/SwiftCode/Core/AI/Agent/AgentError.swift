import Foundation

public enum AgentError: Error, Codable, Sendable {
    case modelError(String)
    case toolError(String)
    case contextError(String)
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .modelError(let msg): return "Model error: \(msg)"
        case .toolError(let msg): return "Tool error: \(msg)"
        case .contextError(let msg): return "Context error: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
