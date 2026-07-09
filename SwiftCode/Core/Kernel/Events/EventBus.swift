import Foundation

/// A central asynchronous event bus for strongly typed events.
public actor EventBus {
    public static let shared = EventBus()

    private var handlers: [String: [Any]] = [:]

    private init() {}

    /// Publishes an event to all subscribers.
    public func publish<T: KernelEvent>(_ event: T) {
        let key = String(describing: T.self)
        guard let subscribers = handlers[key] as? [(T) async -> Void] else { return }

        for subscriber in subscribers {
            Task {
                await subscriber(event)
            }
        }
    }

    /// Subscribes to a specific event type.
    public func subscribe<T: KernelEvent>(_ type: T.Type, handler: @escaping (T) async -> Void) {
        let key = String(describing: T.self)
        var subscribers = handlers[key] as? [(T) async -> Void] ?? []
        subscribers.append(handler)
        handlers[key] = subscribers
    }
}

/// Base protocol for all events on the Kernel Event Bus.
public protocol KernelEvent: Sendable {
    var timestamp: Date { get }
}

/// Example lifecycle event.
public struct LifecycleEvent: KernelEvent {
    public let timestamp = Date()
    public let state: KernelLifecycleState
}
