import Foundation
import Combine

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String
}

struct NetworkRequestLog: Identifiable {
    let id = UUID()
    let url: String
    let method: String
    var statusCode: Int?
    var duration: TimeInterval?
    let timestamp: Date
}

enum LogCategory: String, CaseIterable, Identifiable {
    case networking = "Networking"
    case githubAPI = "GitHub API"
    case deployments = "Deployments"
    case aiProcessing = "AI Processing"
    case storeKit = "StoreKit"
    case extensions = "Extensions"
    case buildSystem = "Build System"

    var id: String { self.rawValue }
}

final class InternalLoggingManager: ObservableObject {
    static let shared = InternalLoggingManager()

    @Published private(set) var logs: [LogEntry] = []
    @Published private(set) var networkLogs: [NetworkRequestLog] = []

    private init() {}

    func log(_ message: String, category: LogCategory) {
        guard FeatureFlags.shared.verbose_logging else { return }

        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), category: category, message: message)
            self.logs.append(entry)

            if self.logs.count > 1000 {
                self.logs.removeFirst()
            }
        }
    }

    func logNetworkRequest(url: String, method: String) -> UUID {
        let entry = NetworkRequestLog(url: url, method: method, timestamp: Date())
        let id = entry.id
        DispatchQueue.main.async {
            self.networkLogs.append(entry)
            if self.networkLogs.count > 100 {
                self.networkLogs.removeFirst()
            }
        }
        return id
    }

    func updateNetworkRequest(id: UUID, statusCode: Int, duration: TimeInterval) {
        DispatchQueue.main.async {
            if let index = self.networkLogs.firstIndex(where: { $0.id == id }) {
                self.networkLogs[index].statusCode = statusCode
                self.networkLogs[index].duration = duration
            }
        }
    }

    func clearLogs() {
        logs = []
        networkLogs = []
    }

    func exportLogs() -> String {
        logs.map { "[\($0.timestamp)] [\($0.category.rawValue)] \($0.message)" }.joined(separator: "\n")
    }
}
