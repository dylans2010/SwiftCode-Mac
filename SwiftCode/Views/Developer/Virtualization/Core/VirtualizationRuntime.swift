import Foundation

public final class VirtualizationRuntime: @unchecked Sendable {
    public static let shared = VirtualizationRuntime()

    private let queue = DispatchQueue(label: "com.swiftcode.virtualization.runtime", attributes: .concurrent)
    private var activeSessions: [UUID: ActiveVMSession] = [:]

    private init() {}

    public struct ActiveVMSession: Sendable {
        public let vmID: UUID
        public let startTime: Date
        public let consoleHistory: [String]
        public let statsTimer: Timer?
    }

    public func registerSession(id: UUID, statsTimer: Timer? = nil) {
        queue.async(flags: .barrier) {
            let session = ActiveVMSession(
                vmID: id,
                startTime: Date(),
                consoleHistory: ["Booting Kernel...", "Mounting /dev...", "Starting systemd services..."],
                statsTimer: statsTimer
            )
            self.activeSessions[id] = session
        }
    }

    public func removeSession(id: UUID) {
        queue.async(flags: .barrier) {
            if let session = self.activeSessions[id] {
                session.statsTimer?.invalidate()
                self.activeSessions.removeValue(forKey: id)
            }
        }
    }

    public func hasSession(_ id: UUID) -> Bool {
        queue.sync {
            return activeSessions[id] != nil
        }
    }

    public func getSession(_ id: UUID) -> ActiveVMSession? {
        queue.sync {
            return activeSessions[id]
        }
    }
}
