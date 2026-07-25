import Foundation

public enum CloudProviderType: String, Codable, CaseIterable, Sendable {
    case supabase = "Supabase"
    case icloud = "iCloud"
    case none = "None"
}

public protocol CloudProvider: AnyObject, Sendable {
    var type: CloudProviderType { get }
    var isEnabled: Bool { get }
    var name: String { get }

    func initialize() async throws
    func testConnection() async -> Bool
}
