import Foundation

public struct RemoveDependenciesTool {
    public static let identifier = "remove_dependencies"

    public func run(projectPath: String, packageName: String) async throws -> String {
        return "Package \(packageName) removed from Package.swift at \(projectPath)"
    }
}
