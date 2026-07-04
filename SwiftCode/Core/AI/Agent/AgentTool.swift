import Foundation

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: [String: JSON] { get }

    func execute(arguments: [String: JSON]) async throws -> String
}
