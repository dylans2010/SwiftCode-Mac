import Foundation

/// Centralized configuration management for the Kernel.
public actor ConfigManager: KernelService {
    public let id = "com.swiftcode.kernel.config"

    private var settings: [String: Any] = [:]
    private let fm = FileManager.default
    private let configURL: URL

    public init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.configURL = docs.appendingPathComponent("kernel_config.json")
    }

    public func initialize() async throws {
        if fm.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.settings = json
            }
        }
        print("[Config] Configuration initialized with \(settings.count) keys.")
    }

    public func get<T>(_ key: String) -> T? {
        return settings[key] as? T
    }

    public func set(_ value: Any, for key: String) async throws {
        settings[key] = value
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: configURL, options: .atomic)
    }
}
