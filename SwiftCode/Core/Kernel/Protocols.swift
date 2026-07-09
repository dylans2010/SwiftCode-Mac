import Foundation

/// Base protocol for all components managed by the Kernel.
public protocol KernelComponent: Sendable {
    var id: String { get }
}

/// Lifecycle states for Kernel modules and services.
public enum KernelLifecycleState: String, Sendable {
    case uninitialized
    case initializing
    case initialized
    case starting
    case started
    case stopping
    case stopped
    case failed
}

/// Protocol for a Kernel Service (Dependency Injection).
public protocol KernelService: KernelComponent {
    func initialize() async throws
}

/// Protocol for a Kernel Module (Feature/Subsystem).
public protocol KernelModule: KernelComponent {
    var version: String { get }
    var priority: Int { get }
    var dependencies: [String] { get }

    func initialize() async throws
    func startup() async throws
    func shutdown() async throws
}

/// Health status of a Kernel component.
public enum KernelHealthStatus: String, Sendable {
    case healthy
    case warning
    case degraded
    case offline
    case failed
}

/// Capability exposed by a module.
public protocol KernelCapability: Sendable {
    var name: String { get }
}
