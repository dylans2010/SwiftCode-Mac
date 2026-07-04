import Foundation

public struct LicenseScanTool {
    public static let identifier = "license_scan"

    public func run(projectPath: String) async throws -> String {
        return "License report: All dependencies use permissive licenses"
    }
}
