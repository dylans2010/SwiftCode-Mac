import Foundation
import SwiftUI
import Observation

public struct SavedCustomEndpoint: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var name: String
    public var endpoint: String
    public var apiKey: String = ""
    public var headers: [HeaderItem] = []
    public var models: [String] = []
    public var showInPopup: Bool = true
    public var isLocal: Bool = false
    public var localPort: String = ""

    public init(id: UUID = UUID(), name: String, endpoint: String, apiKey: String = "", headers: [HeaderItem] = [], models: [String] = [], showInPopup: Bool = true, isLocal: Bool = false, localPort: String = "") {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.headers = headers
        self.models = models
        self.showInPopup = showInPopup
        self.isLocal = isLocal
        self.localPort = localPort
    }
}

@Observable
@MainActor
public final class CustomEndpointManager {
    public static let shared = CustomEndpointManager()

    public var endpoints: [SavedCustomEndpoint] = [] {
        didSet {
            save()
        }
    }

    private init() {
        load()
    }

    public func save() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.custom_endpoints")
        }
    }

    public func load() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.custom_endpoints"),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: data) {
            endpoints = decoded
        } else {
            // Populate with a default custom endpoint if empty
            endpoints = []
        }
    }
}
