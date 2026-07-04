import Foundation

public struct GenerateIntegrationTestsTool {
    public static let identifier = "generate_integration_tests"

    public func run(code: String) async throws -> String {
        return "import XCTest\nclass GeneratedIntegrationTests: XCTestCase {}"
    }
}
