import Foundation

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: [String: Any] { get }

    func execute(arguments: [String: Any]) async throws -> String
}
