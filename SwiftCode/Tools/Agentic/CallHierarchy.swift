import Foundation

public struct CallHierarchyTool {
    public static let identifier = "call_hierarchy"

    public func run(symbol: String) async throws -> String {
        return "Call hierarchy for \(symbol)"
    }
}
