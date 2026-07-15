import Foundation
import SwiftUI
import Observation
import AppKit

@Observable
@MainActor
public final class WorkspaceState {
    public var selectedDocumentID: UUID? = nil
    public var searchActive: Bool = false
    public var searchQuery: String = ""
    public var showBrowserSheet: Bool = false
    public var showLivePreview: Bool = true
    public var showLeftSidebar: Bool = true
    public var showRightInspector: Bool = true

    public init() {}
}

@Observable
@MainActor
public final class PersonalDocumentationCoordinator {
    // AppKit Sidebar Properties
    public var outlineView: NSOutlineView? = nil

    // Isolated Workspace States
    public var workspaceStates: [ModuleKind: WorkspaceState] = [:]

    public func state(for kind: ModuleKind) -> WorkspaceState {
        if let existing = workspaceStates[kind] {
            return existing
        }
        let newState = WorkspaceState()
        workspaceStates[kind] = newState
        return newState
    }
    public var nodes: [SidebarNode] = []
    public let projectID: UUID
    public let projectURL: URL

    // Core Managers
    public let storage: StorageManager
    public let documents: DocumentManager
    public let dashboard: DashboardManager
    public let journal: JournalManager
    public let planning: PlanningManager
    public let wiki: WikiManager
    public let research: ResearchManager
    public let aiContext: AIContextManager
    public let aiAnalysis: AIAnalysisManager
    public let search: SearchManager
    public let indexing: IndexingManager
    public let attachments: AttachmentManager
    public let metadata: MetadataManager
    public let relationships: RelationshipManager
    public let analytics: AnalyticsManager
    public let versionHistory: VersionHistoryManager
    public let exporter: ExportManager
    public let importer: ImportManager
    public let templates: TemplateManager

    // Ecosystem Extensions
    public let whiteboards: WhiteboardManager
    public let snippets: SnippetManager
    public let snapshots: SnapshotManager
    public let timeline: EcosystemTimelineManager
    public let intelligence: IntelligenceManager

    // Navigation state
    public var selectedModuleKind: ModuleKind? = .dashboard {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var selectedDocumentID: UUID? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var selectedWikiPageID: UUID? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var selectedWhiteboardID: UUID? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var selectedSnippetID: UUID? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var selectedSnapshotID: UUID? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("PersonalDocSelectionChanged"), object: nil)
        }
    }
    public var searchActive: Bool = false
    public var isFullScreen: Bool = false
    public var navigationPath = NavigationPath()

    public init(projectID: UUID, projectURL: URL) throws {
        self.projectID = projectID
        self.projectURL = projectURL

        // Initialize Core Managers
        let storageManager = try StorageManager(projectURL: projectURL)
        self.storage = storageManager

        let documentManager = DocumentManager(storage: storageManager, projectID: projectID)
        self.documents = documentManager

        self.dashboard = DashboardManager(documentManager: documentManager)
        self.journal = JournalManager(documentManager: documentManager)
        self.planning = PlanningManager(documentManager: documentManager)
        self.wiki = WikiManager(storage: storageManager, projectID: projectID)
        self.research = ResearchManager(documentManager: documentManager)
        self.aiContext = AIContextManager(projectID: projectID)
        self.aiAnalysis = AIAnalysisManager(projectID: projectID)
        self.indexing = IndexingManager()
        self.search = SearchManager(documentManager: documentManager, indexingManager: self.indexing)
        self.attachments = AttachmentManager(projectURL: projectURL)
        self.metadata = MetadataManager(documentManager: documentManager)
        self.relationships = RelationshipManager(storage: storageManager, projectID: projectID)
        self.analytics = AnalyticsManager(storage: storageManager, projectID: projectID)
        self.versionHistory = VersionHistoryManager(storage: storageManager, projectID: projectID)
        self.exporter = ExportManager()
        self.importer = ImportManager()
        self.templates = TemplateManager(storage: storageManager, projectID: projectID)

        // Initialize Ecosystem Extensions
        self.whiteboards = WhiteboardManager(storage: storageManager, projectID: projectID)
        self.snippets = SnippetManager(storage: storageManager, projectID: projectID)
        self.snapshots = SnapshotManager(storage: storageManager, projectID: projectID)
        self.timeline = EcosystemTimelineManager(storage: storageManager, projectID: projectID)
        self.intelligence = IntelligenceManager(projectID: projectID)

        // Initialize AppKit Sidebar elements
        self.nodes = buildSidebarNodes()

        try? self.templates.seedDefaultTemplates()
        try? self.analytics.logEvent("coordinator_initialized")
    }

    public func navigate(to module: ModuleKind) {
        self.selectedModuleKind = module
        self.selectedDocumentID = nil
        self.searchActive = false
    }

    public func selectDocument(_ id: UUID) {
        self.selectedDocumentID = id
    }
}
