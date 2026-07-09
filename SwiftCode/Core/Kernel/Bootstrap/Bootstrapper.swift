import Foundation

/// Coordinates the application bootstrap sequence.
public actor Bootstrapper {
    public static let shared = Bootstrapper()

    public enum Stage: String, CaseIterable, Sendable {
        case kernelInit
        case configLoad
        case serviceRegistration
        case moduleDiscovery
        case moduleInitialization
        case moduleStartup
        case uiReady
    }

    private var currentStage: Stage = .kernelInit
    private var timings: [Stage: TimeInterval] = [:]

    private init() {}

    public func bootstrap() async throws {
        for stage in Stage.allCases {
            let start = Date()
            currentStage = stage

            try await execute(stage: stage)

            timings[stage] = Date().timeIntervalSince(start)
            let diagnostics = try? await Kernel.shared.resolve(DiagnosticsProvider.self)
            await diagnostics?.recordMetric(timings[stage]!, for: "bootstrap.stage.\(stage.rawValue)")
        }

        await EventBus.shared.publish(LifecycleEvent(state: .started))
    }

    private func execute(stage: Stage) async throws {
        let kernel = Kernel.shared
        switch stage {
        case .kernelInit:
            break
        case .configLoad:
            let config = ConfigManager()
            try await config.initialize()
            await kernel.register(service: config, for: ConfigManager.self)
        case .serviceRegistration:
            await kernel.register(service: HealthMonitor(), for: HealthMonitor.self)
            await kernel.register(service: DiagnosticsProvider(), for: DiagnosticsProvider.self)
            await kernel.register(service: SecurityRuntime(), for: SecurityRuntime.self)
            await kernel.register(service: CapabilityRegistry(), for: CapabilityRegistry.self)
            await kernel.register(service: ResourceManager(), for: ResourceManager.self)

            await kernel.register(service: ProjectManager.shared, for: ProjectManager.self)
            await kernel.register(service: CodingManager.shared, for: CodingManager.self)
            await kernel.register(service: AppSettings.shared, for: AppSettings.self)

        case .moduleDiscovery:
            try await kernel.register(module: AIRuntime())
            try await kernel.register(module: WorkspaceRuntime())
            try await kernel.register(module: LanguageRuntime())
            try await kernel.register(module: PluginRuntime())

        case .moduleInitialization:
            // Modules are already initialized during registration in the registry.
            break
        case .moduleStartup:
            try await kernel.startupModules()

        case .uiReady:
            LoggingTool.info("Kernel Bootstrap Complete. IDE is ready.")
        }
    }
}
