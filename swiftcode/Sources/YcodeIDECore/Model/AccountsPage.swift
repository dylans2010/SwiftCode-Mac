import Foundation

public enum AccountsPage {
    public static let title = "Accounts"
    public static let emptyText = "No Accounts"
    public static let addLabel = "Add account"
    public static let sheetTitle = "Accounts Are Not Supported"

    public static func explanation(keychain: Bool) -> String {
        let source = keychain ? "identities already in your keychain" : "identities SwiftCode finds on this computer"
        return "SwiftCode does not sign in to accounts. Signing uses \(source); SwiftCode never asks for or stores passwords."
    }

    public static var explanation: String {
        #if os(macOS)
        explanation(keychain: true)
        #else
        explanation(keychain: false)
        #endif
    }

    public struct Row: Hashable, Sendable {
        public var title: String
        public var detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    public static func rows(from store: any AppStoreConnectKeyStore) -> [Row] {
        store.keys().map { Row(title: "App Store Connect API Key", detail: $0.keyID) }
    }
}

public struct AppStoreConnectAPIKey: Hashable, Sendable, Codable {
    public var keyID: String
    public var issuerID: String
    public var keyFile: URL

    public init(keyID: String, issuerID: String, keyFile: URL) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.keyFile = keyFile
    }
}

public protocol AppStoreConnectKeyStore: Sendable {
    func keys() -> [AppStoreConnectAPIKey]
}

public struct NoAppStoreConnectKeys: AppStoreConnectKeyStore {
    public init() {}
    public func keys() -> [AppStoreConnectAPIKey] { [] }
}

public enum SettingsPaneOrder {
    public static let all = ["General", "Appearance", "Accounts", "Coding Assistant", "Behaviors", "Navigation", "Notifications",
                             "Editing", "Shortcuts", "Source Control", "Components", "Locations", "Simulators"]
    public static let notOnLinux: Set = ["Simulators"]
    public static var linux: [String] { all.filter { !notOnLinux.contains($0) } }
}
