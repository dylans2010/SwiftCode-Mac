import Foundation

public struct GenerateUnitTestsTool {
    public static let identifier = "generate_unit_tests"

    public func run(code: String) async throws -> String {
        return "import XCTest\nclass GeneratedTests: XCTestCase {}"
    }
}
