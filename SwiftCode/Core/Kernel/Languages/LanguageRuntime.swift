import Foundation

/// Central runtime for language support (parsers, formatters, linters).
public actor LanguageRuntime: KernelModule {
    public let id = "com.swiftcode.runtime.languages"
    public let version = "1.0.0"
    public let priority = 700
    public let dependencies: [String] = []

    private var languages: [String: LanguageConfiguration] = [:]

    public init() {}

    public func initialize() async throws {
        print("[LanguageRuntime] Initializing Language Support...")
    }

    public func startup() async throws {
        print("[LanguageRuntime] Language Runtime started.")
    }

    public func shutdown() async throws {
        languages.removeAll()
        print("[LanguageRuntime] Language Runtime shut down.")
    }

    public func registerLanguage(_ config: LanguageConfiguration) {
        languages[config.extension] = config
    }
}

public struct LanguageConfiguration: Sendable {
    public let name: String
    public let `extension`: String
}
