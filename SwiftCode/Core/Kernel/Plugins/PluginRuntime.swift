import Foundation

/// Manages dynamic loading and lifecycle of IDE plugins.
public actor PluginRuntime: KernelModule {
    public let id = "com.swiftcode.runtime.plugins"
    public let version = "1.0.0"
    public let priority = 600
    public let dependencies: [String] = []

    private var loadedPlugins: [String: PluginInfo] = [:]

    public init() {}

    public func initialize() async throws {
        LoggingTool.info("Plugin Runtime initializing...")
    }

    public func startup() async throws {
        LoggingTool.info("Plugin Runtime started.")
    }

    public func shutdown() async throws {
        loadedPlugins.removeAll()
        LoggingTool.info("Plugin Runtime shut down.")
    }
}

public struct PluginInfo: Sendable {
    let id: String
    let name: String
}
