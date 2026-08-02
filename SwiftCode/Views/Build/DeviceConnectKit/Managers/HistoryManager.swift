import Foundation
import Observation

@Observable
@MainActor
public final class HistoryManager {
    public static let shared = HistoryManager()

    public private(set) var historyItems: [DeploymentHistory] = []

    private init() {}

    public func addHistoryItem(_ item: DeploymentHistory) {
        historyItems.insert(item, at: 0)
    }

    public func removeHistoryItem(_ item: DeploymentHistory) {
        historyItems.removeAll(where: { $0.id == item.id })
    }

    public func clearHistory() {
        historyItems.removeAll()
    }
}
