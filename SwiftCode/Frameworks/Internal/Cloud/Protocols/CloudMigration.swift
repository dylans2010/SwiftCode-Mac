import Foundation

public enum CloudMigrationStrategy: String, Codable, Sendable {
    case mergeLocalAndCloud
    case replaceLocal
    case replaceCloud
}

public protocol CloudMigration: AnyObject, Sendable {
    func migrate(from source: CloudProviderType, to target: CloudProviderType, strategy: CloudMigrationStrategy) async throws
}
