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

    private let userDefaultsKey = "com.swiftcode.custom_endpoints"
    private let manuallyClearedKey = "com.swiftcode.custom_endpoints.manually_cleared"
    private let keychainKey = "com.swiftcode.custom_endpoints.persistent_backup"

    private var homeDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".swiftcode", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("custom_endpoints.json")
    }

    private var appSupportURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("SwiftCode", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("custom_endpoints.json")
    }

    private init() {
        self.endpoints = []
        load()
    }

    /// Manually deletes an endpoint by ID. This is the only way endpoints can be removed.
    func deleteEndpoint(id: UUID) {
        endpoints.removeAll { $0.id == id }
        if endpoints.isEmpty {
            UserDefaults.standard.set(true, forKey: manuallyClearedKey)
            // Also write empty state to persistent storage
            try? Data("[]".utf8).write(to: homeDirectoryURL, options: .atomic)
            if let appSupport = appSupportURL {
                try? Data("[]".utf8).write(to: appSupport, options: .atomic)
            }
            KeychainService.shared.delete(forKey: keychainKey)
        }
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(endpoints) else { return }

        // 1. UserDefaults
        UserDefaults.standard.set(data, forKey: userDefaultsKey)

        if !endpoints.isEmpty {
            UserDefaults.standard.set(false, forKey: manuallyClearedKey)

            // 2. Persistent Home Directory (~/.swiftcode/custom_endpoints.json)
            // Survives app deletion, Xcode DerivedData wipes, and app rebuilds
            try? data.write(to: homeDirectoryURL, options: .atomic)

            // 3. Application Support (Secondary backup)
            if let appSupport = appSupportURL {
                try? data.write(to: appSupport, options: .atomic)
            }

            // 4. macOS Keychain (Tertiary backup - persists across bundle deletion)
            if let jsonString = String(data: data, encoding: .utf8) {
                KeychainService.shared.set(jsonString, forKey: keychainKey)
            }
        }
    }

    func load() {
        // Priority 1: Check UserDefaults
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: data),
           !decoded.isEmpty {
            self.endpoints = decoded
            syncPersistentStores(data: data)
            return
        }

        // Check if user manually deleted all endpoints previously
        let wasManuallyCleared = UserDefaults.standard.bool(forKey: manuallyClearedKey)

        // Priority 2: Persistent Home Directory (~/.swiftcode/custom_endpoints.json)
        // This is the primary safety net when app is deleted or rebuilt
        if FileManager.default.fileExists(atPath: homeDirectoryURL.path),
           let fileData = try? Data(contentsOf: homeDirectoryURL),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: fileData) {
            if !decoded.isEmpty || !wasManuallyCleared {
                if !decoded.isEmpty {
                    self.endpoints = decoded
                    UserDefaults.standard.set(fileData, forKey: userDefaultsKey)
                    UserDefaults.standard.set(false, forKey: manuallyClearedKey)
                    syncPersistentStores(data: fileData)
                    return
                }
            }
        }

        // Priority 3: Application Support Directory
        if let appSupport = appSupportURL,
           FileManager.default.fileExists(atPath: appSupport.path),
           let fileData = try? Data(contentsOf: appSupport),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: fileData),
           !decoded.isEmpty {
            self.endpoints = decoded
            UserDefaults.standard.set(fileData, forKey: userDefaultsKey)
            syncPersistentStores(data: fileData)
            return
        }

        // Priority 4: macOS Keychain Backup
        if let keychainJson = KeychainService.shared.get(forKey: keychainKey),
           let kcData = keychainJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([SavedCustomEndpoint].self, from: kcData),
           !decoded.isEmpty {
            self.endpoints = decoded
            UserDefaults.standard.set(kcData, forKey: userDefaultsKey)
            syncPersistentStores(data: kcData)
            return
        }

        self.endpoints = []
    }

    private func syncPersistentStores(data: Data) {
        try? data.write(to: homeDirectoryURL, options: .atomic)
        if let appSupport = appSupportURL {
            try? data.write(to: appSupport, options: .atomic)
        }
        if let jsonString = String(data: data, encoding: .utf8) {
            KeychainService.shared.set(jsonString, forKey: keychainKey)
        }
    }
}
