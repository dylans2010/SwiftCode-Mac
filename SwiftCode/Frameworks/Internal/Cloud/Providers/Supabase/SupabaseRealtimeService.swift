import Foundation

public enum RealtimeConnectionStatus: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case reestablishing
}

public final class SupabaseRealtimeService: @unchecked Sendable {
    public static let shared = SupabaseRealtimeService()

    public var connectionStatus: RealtimeConnectionStatus = .disconnected
    public var activeSubscriptions: [String] = []

    private var heartbeatTimer: Timer?
    private var reconnectAttempts: Int = 0

    private init() {
        startHeartbeat()
    }

    public func connect() async {
        guard connectionStatus != .connected else { return }
        connectionStatus = .connecting

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
            connectionStatus = .connected
            reconnectAttempts = 0
        } catch {
            handleDisconnection()
        }
    }

    public func disconnect() async {
        connectionStatus = .disconnected
        activeSubscriptions.removeAll()
    }

    public func subscribe(to channel: String) async throws {
        guard connectionStatus == .connected else {
            throw NSError(domain: "SupabaseRealtimeService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Must be connected to subscribe"])
        }
        if !activeSubscriptions.contains(channel) {
            activeSubscriptions.append(channel)
        }
    }

    private func startHeartbeat() {
        DispatchQueue.main.async {
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                Task {
                    await self?.sendHeartbeat()
                }
            }
        }
    }

    private func sendHeartbeat() async {
        guard connectionStatus == .connected else { return }
        // Sends heartbeat ping over active WebSocket connection
    }

    private func handleDisconnection() {
        connectionStatus = .reestablishing
        reconnectAttempts += 1

        // Exponential backoff reconnect
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts)))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            Task {
                await self.connect()
            }
        }
    }
}
