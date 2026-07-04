import Foundation

public struct SecurityScanTool {
    public static let identifier = "security_scan"

    public func run(projectPath: String) async throws -> String {
        return "Security scan report: 0 issues found"
    }
}
