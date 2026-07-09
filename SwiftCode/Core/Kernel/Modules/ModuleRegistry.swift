import Foundation

/// Manages application modules and their lifecycles.
public actor ModuleRegistry {
    private var modules: [String: KernelModule] = [:]
    private var states: [String: KernelLifecycleState] = [:]

    public init() {}

    public func register(_ module: KernelModule) async throws {
        modules[module.id] = module
        states[module.id] = .uninitialized

        try await module.initialize()
        states[module.id] = .initialized
    }

    public func startupAll() async throws {
        // Topological sort would be ideal here based on dependencies.
        // For now, we use priority as a proxy for dependency order.
        let sortedModules = modules.values.sorted { $0.priority > $1.priority }

        for module in sortedModules {
            // Verify dependencies are met
            for dep in module.dependencies {
                guard states[dep] == .started || states[dep] == .initialized else {
                    throw KernelError.moduleNotFound("Dependency \(dep) not ready for module \(module.id)")
                }
            }

            states[module.id] = .starting
            try await module.startup()
            states[module.id] = .started
        }
    }

    public func shutdownAll() async throws {
        // Shutdown in reverse priority
        let sortedModules = modules.values.sorted { $0.priority < $1.priority }

        for module in sortedModules {
            states[module.id] = .stopping
            try await module.shutdown()
            states[module.id] = .stopped
        }
    }
}
