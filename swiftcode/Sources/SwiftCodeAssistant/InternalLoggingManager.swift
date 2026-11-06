import Foundation
import Observation

// Ported from Legacy `SwiftCode/Backend/Developer/InternalLoggingManager.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Landed verbatim by a parallel agent; adapted by fix W-V2 (A6 slice: LLMService and
// OpenRouterService both call InternalLoggingManager.shared.log).
// Adaptation (one): Combine -> Observation. SwiftCodeAssistant has no Combine (see
// AssistModelManager's header for the in-tree convention): ObservableObject + @Published
// become @Observable + plain stored vars; log() stays sync non-isolated with the
// DispatchQueue.main.async appends as in Legacy. Types stay internal — the only
// callers (LLMService, OpenRouterService) live in this target.


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

@Observable
final class InternalLoggingManager: @unchecked Sendable {
    static let shared = InternalLoggingManager()

    private(set) var logs: [LogEntry] = []
    private(set) var networkLogs: [NetworkRequestLog] = []

    private init() {}

    func log(_ message: String, category: LogCategory) {
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
