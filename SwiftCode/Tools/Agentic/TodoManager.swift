import Foundation

public struct TodoManagerTool {
    public static let identifier = "todo_manager"

    public func run(action: String, todo: String?) async throws -> [String] {
        return ["Todo list updated"]
    }
}
