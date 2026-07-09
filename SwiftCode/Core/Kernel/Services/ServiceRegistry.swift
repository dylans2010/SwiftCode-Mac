import Foundation

/// Defines the lifetime of a service in the registry.
public enum ServiceLifetime: Sendable {
    case singleton
    case transient
    case scoped
}

/// A factory for creating service instances.
public typealias ServiceFactory<T> = @Sendable (ServiceRegistry) async throws -> T

/// Manages dependency injection for the Kernel.
public actor ServiceRegistry {
    private var singletons: [String: Any] = [:]
    private var factories: [String: (ServiceFactory<Any>, ServiceLifetime)] = [:]
    private var resolutionStack: [String] = []

    public init() {}

    public func register<T>(_ type: T.Type, lifetime: ServiceLifetime = .singleton, factory: @escaping ServiceFactory<T>) {
        let key = String(describing: type)
        factories[key] = (factory, lifetime)
    }

    /// Overload for direct instance registration (always singleton)
    public func register<T>(_ instance: T, for type: T.Type) {
        let key = String(describing: type)
        singletons[key] = instance
    }

    public func resolve<T>(_ type: T.Type) async throws -> T {
        let key = String(describing: type)

        // Circular dependency detection
        if resolutionStack.contains(key) {
            throw KernelError.circularDependencyDetected(key)
        }
        resolutionStack.append(key)
        defer { resolutionStack.removeLast() }

        // 1. Check singletons
        if let instance = singletons[key] as? T {
            return instance
        }

        // 2. Check factories
        guard let (factory, lifetime) = factories[key] else {
            throw KernelError.serviceNotFound(key)
        }

        let instance = try await factory(self)
        guard let typedInstance = instance as? T else {
            throw KernelError.initializationFailed("Factory returned wrong type for \(key)")
        }

        if lifetime == .singleton {
            singletons[key] = typedInstance
        }

        return typedInstance
    }
}
