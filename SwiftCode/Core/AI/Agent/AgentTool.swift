import Foundation

public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: [String: any Sendable] { get }

    func execute(arguments: [String: any Sendable]) async throws -> String
}
