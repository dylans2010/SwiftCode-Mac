import Foundation

public enum VirtualizationEvent: Sendable {
    case started(UUID)
    case stopped(UUID)
    case paused(UUID)
    case resumed(UUID)
    case restarted(UUID)
    case error(UUID, String)
    case log(UUID, String)
    case statUpdate(UUID, Double, Double, Double, Double) // CPU, RAM, Network, Disk
    case metadataUpdated(UUID)
    case registryChanged
}

public final class VirtualizationEventBus: @unchecked Sendable {
    public static let shared = VirtualizationEventBus()
    private let queue = DispatchQueue(label: "com.swiftcode.virtualization.eventbus", attributes: .concurrent)
    private var listeners: [@Sendable (VirtualizationEvent) -> Void] = []

    private init() {}

    public func subscribe(_ listener: @escaping @Sendable (VirtualizationEvent) -> Void) {
        queue.async(flags: .barrier) {
            self.listeners.append(listener)
        }
    }

    public func post(_ event: VirtualizationEvent) {
        queue.sync {
            for listener in listeners {
                listener(event)
            }
        }
    }
}
