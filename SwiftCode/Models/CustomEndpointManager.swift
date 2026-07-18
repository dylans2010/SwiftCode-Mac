import Foundation
import SwiftUI
import Observation

struct SavedCustomEndpoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var endpoint: String
    var apiKey: String = ""
    var headers: [HeaderItem] = []
    var models: [String] = []
    var showInPopup: Bool = true
    var isLocal: Bool = false
    var localPort: String = ""

    init(id: UUID = UUID(), name: String, endpoint: String, apiKey: String = "", headers: [HeaderItem] = [], models: [String] = [], showInPopup: Bool = true, isLocal: Bool = false, localPort: String = "") {
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
final class CustomEndpointManager {
    static let shared = CustomEndpointManager()

    var endpoints: [SavedCustomEndpoint] = [] {
        didSet {
            save()
        }
    }

    private init() {
        self.endpoints = []
        load()
    }

    func save() {
        if let data = try? JSONEncoder().encode(endpoints) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.custom_endpoints")
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.custom_endpoints"),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: data) {
            self.endpoints = decoded
        } else {
            self.endpoints = []
        }
    }
}
