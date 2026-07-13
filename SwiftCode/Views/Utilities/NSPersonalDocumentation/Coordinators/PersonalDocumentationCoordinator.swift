import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class PersonalDocumentationCoordinator {
    public let projectID: UUID
    public let projectURL: URL

    // 18 Managers
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

    // Navigation state
    public var selectedModuleKind: ModuleKind? = .dashboard
    public var selectedDocumentID: UUID?
    public var searchActive: Bool = false
    public var navigationPath = NavigationPath()

    public init(projectID: UUID, projectURL: URL) throws {
        self.projectID = projectID
        self.projectURL = projectURL

        // Initialize Managers
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
