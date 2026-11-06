import Foundation
import Observation

/// One header sent with requests to a custom endpoint.
public struct CustomEndpointHeader: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
}

/// A user-configured OpenAI-compatible endpoint (Legacy
/// `SavedCustomEndpoint` / `CustomEndpointManager`).
///
/// Security change, stated plainly: Legacy stored the endpoint's API key
/// in the same plaintext JSON as the endpoint itself (UserDefaults, a
/// `~/.swiftcode` file, Application Support, and a Keychain backup of the
/// same JSON). This port never stores a key in the endpoint record: keys
/// live only in the `SecretStore` (Keychain on macOS, 0600 files on
/// Linux), keyed per endpoint id, and are never encoded with the record.
public struct SavedCustomEndpoint: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var endpoint: String
    public var headers: [CustomEndpointHeader] = []
    public var models: [String] = []
    public var showInPopup: Bool = true
    public var isLocal: Bool = false
    public var localPort: String = ""

    public init(
        id: UUID = UUID(), name: String, endpoint: String,
        headers: [CustomEndpointHeader] = [], models: [String] = [],
        showInPopup: Bool = true, isLocal: Bool = false, localPort: String = ""
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.headers = headers
        self.models = models
        self.showInPopup = showInPopup
        self.isLocal = isLocal
        self.localPort = localPort
    }
}

/// Owns the saved custom endpoints (Legacy `CustomEndpointManager`).
/// Endpoints persist as JSON in Application Support/SwiftCode; API keys persist
/// only in the `SecretStore`. The `endpoints` setter no longer triggers a
/// model-discovery refresh (Legacy did, via `AssistModelDiscoveryService`);
/// callers refresh discovery explicitly after editing endpoints.
@Observable
@MainActor
public final class CustomEndpointManager {
    public static let shared = CustomEndpointManager()

    public var endpoints: [SavedCustomEndpoint] = [] {
        didSet { save() }
    }

    private let secretStore: SecretStore
    private let defaults: UserDefaults

    public init(secretStore: SecretStore? = nil, defaults: UserDefaults = .standard) {
        self.secretStore = secretStore ?? defaultSecretStore()
        self.defaults = defaults
        load()
    }

    public var storeURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent("custom-endpoints.json")
    }

    /// The reduced shape the Muse other-models bridge reads (Legacy
    /// `CustomEndpointManager` endpoint, reduced to what resolution reads).
    public var museEndpoints: [MuseCustomEndpoint] {
        endpoints.map { MuseCustomEndpoint(name: $0.name, models: $0.models, isLocal: $0.isLocal) }
    }

    public func addEndpoint(_ endpoint: SavedCustomEndpoint) {
        endpoints.append(endpoint)
    }

    public func updateEndpoint(_ endpoint: SavedCustomEndpoint) {
        guard let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) else { return }
        endpoints[index] = endpoint
    }

    public func deleteEndpoint(id: UUID) {
        endpoints.removeAll { $0.id == id }
        try? secretStore.delete(keyAccount(for: id))
    }

    public func apiKey(for endpoint: SavedCustomEndpoint) -> String? {
        secretStore.readString(keyAccount(for: endpoint.id))
    }

    public func setAPIKey(_ key: String?, for endpoint: SavedCustomEndpoint) throws {
        if let key, !key.isEmpty {
            try secretStore.write(Data(key.utf8), for: keyAccount(for: endpoint.id))
        } else {
            try secretStore.delete(keyAccount(for: endpoint.id))
        }
    }

    private func keyAccount(for id: UUID) -> String {
        "custom-endpoint-\(id.uuidString)"
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(endpoints) else { return }
        guard let url = storeURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func load() {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: data) else {
            endpoints = []
            return
        }
        endpoints = decoded
    }
}
