import SwiftUI
import Observation

public enum OperationsPanel: String, CaseIterable, Identifiable, Codable {
    case dashboard = "Dashboard"
    case projectRegistry = "Project Registry"
    case archives = "Archive Manager"
    case buildHistory = "Build History"
    case diagnostics = "Diagnostics"
    case dependencies = "Dependencies"
    case storage = "Storage"
    case security = "Security"
    case aiReports = "AI Reports"
    case health = "Workspace Health"
    case logs = "Logging Center"
    case timeline = "Timeline"
    case search = "Search"
    case queue = "Operation Queue"
    case notifications = "Notifications"
    case preferences = "Preferences"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .projectRegistry: return "folder"
        case .archives: return "archivebox"
        case .buildHistory: return "clock"
        case .diagnostics: return "ant"
        case .dependencies: return "puzzlepiece"
        case .storage: return "externaldrive"
        case .security: return "shield"
        case .aiReports: return "sparkles"
        case .health: return "heart.text.square"
        case .logs: return "doc.text.magnifyingglass"
        case .timeline: return "calendar.day.timeline.left"
        case .search: return "magnifyingglass"
        case .queue: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .preferences: return "gearshape"
        }
    }
}

@Observable
@MainActor
public final class OperationsCoordinator {
    public static let shared = OperationsCoordinator()

    public var selectedPanel: OperationsPanel = .dashboard
    public var selectedProjectID: UUID? = nil
    public var selectedArchiveID: UUID? = nil
    public var selectedBuildID: UUID? = nil
    public var searchQuery: String = ""
    public var showInspector: Bool = false
    public var isSidebarCollapsed: Bool = false

    // State of background task queues
    public var activeTaskCount: Int = 0

    private init() {}

    public func selectPanel(_ panel: OperationsPanel) {
        selectedPanel = panel
    }
}
