import Foundation

/// The central runtime for the SwiftCode application.
@globalActor
public actor Kernel {
    public static let shared = Kernel()

    private let serviceRegistry: ServiceRegistry
    private let moduleRegistry: ModuleRegistry

    private var isBootstrapped = false

    private init() {
        self.serviceRegistry = ServiceRegistry()
        self.moduleRegistry = ModuleRegistry()
    }

    /// Entry point for application bootstrapping.
    public func bootstrap() async throws {
        guard !isBootstrapped else { return }
        try await Bootstrapper.shared.bootstrap()
        isBootstrapped = true
    }

    // MARK: - Service Resolution

    public func resolve<T>(_ type: T.Type) async throws -> T {
        return try await serviceRegistry.resolve(type)
    }

    public func register<T>(service: T, for type: T.Type) async {
        await serviceRegistry.register(service, for: type)
        if let kernelService = service as? KernelService {
             try? await kernelService.initialize()
        }
    }

    public func register<T>(_ type: T.Type, lifetime: ServiceLifetime = .singleton, factory: @escaping ServiceFactory<T>) async {
        await serviceRegistry.register(type, lifetime: lifetime, factory: factory)
    }

    // MARK: - Module Management

    public func register(module: KernelModule) async throws {
        try await moduleRegistry.register(module)
    }

    public func startupModules() async throws {
        try await moduleRegistry.startupAll()
    }
}
