import Foundation

public struct CrossReferenceSearchTool {
    public static let identifier = "cross_reference_search"

    public func run(symbol: String) async throws -> [String] {
        return ["References to \(symbol)"]
    }
}
