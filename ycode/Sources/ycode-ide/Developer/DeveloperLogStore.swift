import Foundation

/// In-process log store for the ported developer diagnostic views.
///
/// Legacy's diagnostic views read `InternalLoggingManager.shared`, a
/// Legacy-only in-memory log store that does not exist in Ycode. This is
/// its Ycode-side equivalent: an in-process store that the ported views
/// (Log Console, API Inspector, Network Inspector, API Latency, AI Model
/// Debugger, Deployment Debug, Verbose Logging) read and write. Entries
/// only ever appear when this process actually logs them — an empty store
/// shows an honest empty state, never seeded example traffic.
enum DeveloperLogCategory: String, Codable, CaseIterable {
    case networking
    case githubAPI
    case deployments
    case aiProcessing
    case storeKit
    case extensions
    case buildSystem
}

struct DeveloperLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let category: DeveloperLogCategory
}

struct DeveloperNetworkLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let method: String
    let url: String
    let statusCode: Int?
    let duration: TimeInterval?
}

@Observable
@MainActor
final class DeveloperLogStore {
    static let shared = DeveloperLogStore()

    private(set) var logs: [DeveloperLogEntry] = []
    private(set) var networkLogs: [DeveloperNetworkLogEntry] = []

    func log(_ message: String, category: DeveloperLogCategory) {
        logs.append(DeveloperLogEntry(message: message, category: category))
    }

    func logNetwork(method: String, url: String, statusCode: Int?, duration: TimeInterval?) {
        networkLogs.append(
            DeveloperNetworkLogEntry(method: method, url: url, statusCode: statusCode, duration: duration)
        )
    }

    func clearLogs() {
        logs.removeAll()
        networkLogs.removeAll()
    }

    func exportLogs() -> String {
        logs.map { "[\($0.timestamp)] \($0.category.rawValue): \($0.message)" }.joined(separator: "\n")
    }
}
