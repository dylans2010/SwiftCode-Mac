import Foundation
import Observation
import SwiftCodeIDECore
import SwiftUI

/// Personal Documentation — Legacy's `Views/Utilities/NSPersonalDocumentation/`
/// subsystem, ported onto SwiftCode's systems (spec-first where it costs nothing;
/// Legacy is Dylan's own code, direct porting authorised under MIT).
///
/// Deliberate deviations from Legacy, all in the direction of SwiftCode's rules:
/// - Legacy persisted with SwiftData (`@Model Document`, `ModelContainer`).
///   SwiftCode's IDE has no database layer (UserDefaults + JSON files), so the
///   store here is plain `Codable` models in JSON files under Application
///   Support `SwiftCode/PersonalDocs/<project-hash>/`, one file per collection —
///   the same pattern as `CodingAssistantModel`'s conversation archive.
/// - Legacy's `AIAnalysisManager` called `LLMService.shared` directly. Here
///   analysis goes through an injected `PersonalDocTextProvider`; when none
///   is set the store runs a real local extractive analysis
///   (`PersonalDocLocalAnalyzer`) instead of pretending an LLM answered.
/// - Legacy's per-module `accentColor` (including orange) is dropped; SwiftCode
///   uses the default accent. The module icons (SF Symbol names) are kept.

/// Archetype of a documentation module (Legacy `Archetype`).
public enum PersonalDocArchetype: String, Sendable, Codable, CaseIterable {
    case freeform = "Freeform Document"
    case structured = "Structured Record"
    case generated = "Generated/Derived Document"
    case container = "Container/Organizer"
}

/// A documentation module (Legacy `ModuleKind`, all 55 cases, same raw values).
public enum PersonalDocModuleKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case personalDocumentation = "Personal Documentation"
    case dailyNotes = "Daily Notes"
    case weeklyReviews = "Weekly Reviews"
    case monthlyReviews = "Monthly Reviews"
    case scratchpad = "Scratchpad"
    case learningNotes = "Learning Notes"
    case meetingNotes = "Meeting Notes"
    case researchLibrary = "Research Library"
    case knowledgeBase = "Knowledge Base"
    case ideasVault = "Ideas Vault"
    case buildNotes = "Build Notes"
    case deploymentNotes = "Deployment Notes"
    case terminalHistory = "Terminal History"
    case environmentDocs = "Environment Docs"
    case dependencyDocs = "Dependency Docs"
    case uiUXPlanning = "UI/UX Planning"
    case experimentLog = "Experiment Log"
    case performanceNotes = "Performance Notes"
    case testingNotes = "Testing Notes"
    case qaNotes = "QA Notes"
    case securityNotes = "Security Notes"
    case accessibilityNotes = "Accessibility Notes"
    case technicalSpecification = "Technical Specification"
    case userStory = "User Story"
    case freeformDocument = "Freeform Document"
    case featurePlanning = "Feature Planning"
    case bugDatabase = "Bug Database"
    case techDebtTracker = "Technical Debt Tracker"
    case roadmap = "Roadmap"
    case milestones = "Milestones"
    case releasePlanning = "Release Planning"
    case changelogBuilder = "Changelog Builder"
    case apiDocumentation = "API Documentation"
    case databaseDocumentation = "Database Documentation"
    case releaseChecklist = "Release Checklist"
    case structuredRecord = "Structured Record"
    case projectWiki = "Project Wiki"
    case dashboard = "Dashboard"
    case architectureDecisions = "Architecture Decisions"
    case aiInsights = "AI Insights"
    case smartCollections = "Smart Collections"
    case favorites = "Favorites"
    case archivedDocuments = "Archived Documents"
    case templates = "Templates"
    case bookmarks = "Bookmarks"
    case attachments = "Attachments"
    case images = "Images"
    case referenceLibrary = "Reference Library"
    case knowledgeGraph = "Knowledge Graph"
    case timeline = "Project Timeline"
    case analytics = "Project Analytics"
    case intelligence = "Project Intelligence"
    case whiteboards = "Advanced Whiteboards"
    case snippets = "Snippet Workspace"
    case snapshots = "Project Snapshots"

    public var id: String { rawValue }

    public var archetype: PersonalDocArchetype {
        switch self {
        case .personalDocumentation, .dailyNotes, .weeklyReviews, .monthlyReviews, .scratchpad,
             .learningNotes, .meetingNotes, .researchLibrary, .knowledgeBase, .ideasVault,
             .buildNotes, .deploymentNotes, .terminalHistory, .environmentDocs, .dependencyDocs,
             .uiUXPlanning, .experimentLog, .performanceNotes, .testingNotes, .qaNotes,
             .securityNotes, .accessibilityNotes, .technicalSpecification, .userStory, .freeformDocument:
            return .freeform
        case .featurePlanning, .bugDatabase, .techDebtTracker, .roadmap, .milestones,
             .releasePlanning, .changelogBuilder, .apiDocumentation, .databaseDocumentation,
             .releaseChecklist, .structuredRecord:
            return .structured
        case .projectWiki, .dashboard, .architectureDecisions, .aiInsights,
             .knowledgeGraph, .timeline, .analytics, .intelligence, .whiteboards, .snippets, .snapshots:
            return .generated
        case .smartCollections, .favorites, .archivedDocuments, .templates, .bookmarks,
             .attachments, .images, .referenceLibrary:
            return .container
        }
    }

    public var icon: String {
        switch self {
        case .personalDocumentation: return "doc.text.fill"
        case .dailyNotes: return "calendar.day.timeline.left"
        case .weeklyReviews: return "calendar.badge.clock"
        case .monthlyReviews: return "calendar"
        case .scratchpad: return "note.text"
        case .learningNotes: return "book.closed.fill"
        case .meetingNotes: return "person.2.wave.2.fill"
        case .researchLibrary: return "archivebox.fill"
        case .knowledgeBase: return "brain.head.profile"
        case .ideasVault: return "lightbulb.fill"
        case .buildNotes: return "hammer.fill"
        case .deploymentNotes: return "cloud.fill"
        case .terminalHistory: return "terminal.fill"
        case .environmentDocs: return "leaf.fill"
        case .dependencyDocs: return "puzzlepiece.fill"
        case .uiUXPlanning: return "paintpalette.fill"
        case .experimentLog: return "testtube.2"
        case .performanceNotes: return "gauge.with.needle"
        case .testingNotes: return "checklist"
        case .qaNotes: return "checkmark.seal.fill"
        case .securityNotes: return "shield.fill"
        case .accessibilityNotes: return "figure.roll"
        case .technicalSpecification: return "doc.text.fill"
        case .userStory: return "doc.text.image"
        case .freeformDocument: return "doc.text"
        case .featurePlanning: return "slider.horizontal.3"
        case .bugDatabase: return "ladybug.fill"
        case .techDebtTracker: return "chart.line.flattest.curve"
        case .roadmap: return "map.fill"
        case .milestones: return "flag.fill"
        case .releasePlanning: return "shippingbox.fill"
        case .changelogBuilder: return "doc.text.below.ecg.fill"
        case .apiDocumentation: return "network"
        case .databaseDocumentation: return "cylinder.split.1x2.fill"
        case .releaseChecklist: return "shippingbox.fill"
        case .structuredRecord: return "tablecells"
        case .projectWiki: return "globe.americas.fill"
        case .dashboard: return "square.grid.2x2.fill"
        case .architectureDecisions: return "gavel.fill"
        case .aiInsights: return "sparkles"
        case .smartCollections: return "folder.badge.gearshape"
        case .favorites: return "star.fill"
        case .archivedDocuments: return "tray.and.arrow.down.fill"
        case .templates: return "doc.on.doc.fill"
        case .bookmarks: return "bookmark.fill"
        case .attachments: return "paperclip"
        case .images: return "photo.fill"
        case .referenceLibrary: return "books.vertical.fill"
        case .knowledgeGraph: return "circle.grid.3x3.fill"
        case .timeline: return "calendar.day.timeline.left"
        case .analytics: return "chart.bar.xaxis"
        case .intelligence: return "brain.head.profile"
        case .whiteboards: return "pencil.and.outline"
        case .snippets: return "text.badge.plus"
        case .snapshots: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }

    /// Accent colour (Legacy `ModuleKind.accentColor` logic). Added so the
    /// ported `GlobalSearchView` can colour rows by module kind; the enum
    /// previously had `icon` but no colour.
    public var accentColor: Color {
        switch self {
        case .knowledgeGraph, .intelligence: return .purple
        case .timeline, .whiteboards: return .blue
        case .analytics, .snapshots: return .orange
        case .snippets: return .green
        default:
            switch self.archetype {
            case .freeform: return .blue
            case .structured: return .orange
            case .generated: return .purple
            case .container: return .green
            }
        }
    }
}

/// A documentation record (Legacy `Document`, as a value type).
public struct PersonalDocDocument: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var archetype: String
    public var moduleKind: PersonalDocModuleKind
    public var title: String
    public var markdownSource: String
    public var attachments: [UUID]
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var pinned: Bool
    public var archived: Bool
    public var status: String?
    public var priority: String?
    public var severity: String?
    public var reproSteps: String?
    public var stackTrace: String?
    public var targetQuarter: String?
    public var dependencyIDs: [UUID]

    public init(
        id: UUID = UUID(), projectID: UUID, archetype: String = PersonalDocArchetype.freeform.rawValue,
        moduleKind: PersonalDocModuleKind, title: String, markdownSource: String = "",
        attachments: [UUID] = [], tags: [String] = [], createdAt: Date = Date(),
        updatedAt: Date = Date(), pinned: Bool = false, archived: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.archetype = archetype
        self.moduleKind = moduleKind
        self.title = title
        self.markdownSource = markdownSource
        self.attachments = attachments
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.archived = archived
        self.dependencyIDs = []
    }
}

public struct PersonalDocTemplate: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID?
    public var moduleKind: PersonalDocModuleKind
    public var title: String
    public var descriptionText: String
    public var markdownSource: String
    public init(id: UUID = UUID(), projectID: UUID? = nil, moduleKind: PersonalDocModuleKind, title: String, descriptionText: String, markdownSource: String) {
        self.id = id; self.projectID = projectID; self.moduleKind = moduleKind
        self.title = title; self.descriptionText = descriptionText; self.markdownSource = markdownSource
    }
}

public struct PersonalDocWikiPage: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var markdownSource: String
    public var lastUpdated: Date
    public var isStale: Bool
    public init(id: UUID = UUID(), projectID: UUID, title: String, markdownSource: String = "", lastUpdated: Date = Date(), isStale: Bool = false) {
        self.id = id; self.projectID = projectID; self.title = title
        self.markdownSource = markdownSource; self.lastUpdated = lastUpdated; self.isStale = isStale
    }
}

public struct PersonalDocVersion: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var documentID: UUID
    public var titleSnapshot: String
    public var markdownSnapshot: String
    public var timestamp: Date
    public init(id: UUID = UUID(), projectID: UUID, documentID: UUID, titleSnapshot: String, markdownSnapshot: String, timestamp: Date = Date()) {
        self.id = id; self.projectID = projectID; self.documentID = documentID
        self.titleSnapshot = titleSnapshot; self.markdownSnapshot = markdownSnapshot; self.timestamp = timestamp
    }
}

public struct PersonalDocRelationship: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var sourceDocumentID: UUID
    public var targetType: String
    public var targetIdentifier: String
    public var targetName: String
    public var createdAt: Date
    public init(id: UUID = UUID(), projectID: UUID, sourceDocumentID: UUID, targetType: String, targetIdentifier: String, targetName: String, createdAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.sourceDocumentID = sourceDocumentID
        self.targetType = targetType; self.targetIdentifier = targetIdentifier
        self.targetName = targetName; self.createdAt = createdAt
    }
}

public struct PersonalDocAttachment: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var relativePath: String
    public var originalFileName: String
    public var mimeType: String
    public var fileSize: Int64
    public var addedAt: Date
    public init(id: UUID = UUID(), projectID: UUID, relativePath: String, originalFileName: String, mimeType: String, fileSize: Int64, addedAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.relativePath = relativePath
        self.originalFileName = originalFileName; self.mimeType = mimeType
        self.fileSize = fileSize; self.addedAt = addedAt
    }
}

public struct PersonalDocSmartCollection: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var includedTags: [String]
    public var archetypeFilter: String?
    public init(id: UUID = UUID(), projectID: UUID, title: String, includedTags: [String] = [], archetypeFilter: String? = nil) {
        self.id = id; self.projectID = projectID; self.title = title
        self.includedTags = includedTags; self.archetypeFilter = archetypeFilter
    }
}

public struct PersonalDocAIInsight: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var kind: String
    public var generatedAt: Date
    public var sourceDocumentIDs: [UUID]
    public var content: String
    public var isStale: Bool
    public init(id: UUID = UUID(), projectID: UUID, kind: String, generatedAt: Date = Date(), sourceDocumentIDs: [UUID] = [], content: String, isStale: Bool = false) {
        self.id = id; self.projectID = projectID; self.kind = kind; self.generatedAt = generatedAt
        self.sourceDocumentIDs = sourceDocumentIDs; self.content = content; self.isStale = isStale
    }
}

public struct PersonalDocAnalyticsEvent: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var timestamp: Date
    public var eventName: String
    public var metadata: [String: String]?
    public init(id: UUID = UUID(), projectID: UUID, timestamp: Date = Date(), eventName: String, metadata: [String: String]? = nil) {
        self.id = id; self.projectID = projectID; self.timestamp = timestamp
        self.eventName = eventName; self.metadata = metadata
    }
}

public struct PersonalDocWhiteboard: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    /// Nodes, shapes, connectors and drawings, encoded as JSON (Legacy stored the same blob).
    public var elementsJSON: String
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), projectID: UUID, title: String, elementsJSON: String = "[]", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.title = title; self.elementsJSON = elementsJSON
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct PersonalDocSnippet: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var code: String
    public var language: String
    public var category: String
    public var tags: [String]
    public var isFavorite: Bool
    public var versionHistory: [String]
    public var createdAt: Date
    public init(id: UUID = UUID(), projectID: UUID, title: String, code: String, language: String, category: String, tags: [String] = [], isFavorite: Bool = false, versionHistory: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.title = title; self.code = code
        self.language = language; self.category = category; self.tags = tags
        self.isFavorite = isFavorite; self.versionHistory = versionHistory; self.createdAt = createdAt
    }
}

/// A point-in-time capture of the documentation workspace (Legacy
/// `ProjectSnapshotRecord`). The ID lists name what the snapshot holds;
/// the JSON payloads hold the full content at capture time, so restoring
/// recovers edited or deleted content instead of only archiving /
/// un-archiving whatever still exists. New fields default to `"[]"` so
/// snapshots written before this change still decode.
public struct PersonalDocSnapshot: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var projectID: UUID
    public var title: String
    public var description: String
    public var documentIDs: [UUID]
    public var whiteboardIDs: [UUID]
    public var snippetIDs: [UUID]
    /// Full `PersonalDocDocument` records at capture time (Legacy
    /// `ProjectSnapshotRecord.documentsJSON`).
    public var documentsJSON: String
    /// Full `PersonalDocWhiteboard` records at capture time (Legacy
    /// `ProjectSnapshotRecord.whiteboardsJSON`).
    public var whiteboardsJSON: String
    /// Full `PersonalDocSnippet` records at capture time (Legacy
    /// `ProjectSnapshotRecord.snippetsJSON`).
    public var snippetsJSON: String
    public var createdAt: Date
    public init(id: UUID = UUID(), projectID: UUID, title: String, description: String, documentIDs: [UUID] = [], whiteboardIDs: [UUID] = [], snippetIDs: [UUID] = [], documentsJSON: String = "[]", whiteboardsJSON: String = "[]", snippetsJSON: String = "[]", createdAt: Date = Date()) {
        self.id = id; self.projectID = projectID; self.title = title; self.description = description
        self.documentIDs = documentIDs; self.whiteboardIDs = whiteboardIDs
        self.snippetIDs = snippetIDs; self.createdAt = createdAt
        self.documentsJSON = documentsJSON; self.whiteboardsJSON = whiteboardsJSON
        self.snippetsJSON = snippetsJSON
    }
}

public struct PersonalDocTimelineItem: Identifiable, Sendable, Hashable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var category: String // "document", "whiteboard", "snippet", "ai"
    public var date: Date
    public var tags: [String]
    public init(id: UUID = UUID(), title: String, detail: String, category: String, date: Date, tags: [String] = []) {
        self.id = id; self.title = title; self.detail = detail
        self.category = category; self.date = date; self.tags = tags
    }
}

public struct PersonalDocSearchResult: Identifiable, Sendable {
    public var id: UUID { document.id }
    public let document: PersonalDocDocument
    public let score: Int
    public let snippet: String
}

/// A structured-record field schema (Legacy `ModuleFieldSchema`).
public struct PersonalDocFieldSchema: Sendable, Codable {
    public var fields: [FieldDefinition]
    public struct FieldDefinition: Sendable, Codable, Identifiable {
        public var id: String { name }
        public let name: String
        public let label: String
        public let type: FieldType
        public let isRequired: Bool
        public init(name: String, label: String, type: FieldType, isRequired: Bool = false) {
            self.name = name; self.label = label; self.type = type; self.isRequired = isRequired
        }
    }
    public enum FieldType: String, Sendable, Codable {
        case text, longText, number, date, boolean, singleSelect, multiSelect, url
    }
    public init(fields: [FieldDefinition] = []) { self.fields = fields }
}

/// The text-generation seam for AI analysis. Legacy called its own
/// `LLMService` directly; SwiftCode routes text generation through the coding
/// assistant's providers. A host wires a provider-backed implementation here;
/// with none set, analysis falls back to `PersonalDocLocalAnalyzer`.
public protocol PersonalDocTextProvider: Sendable {
    func generate(prompt: String) async throws -> String
}

/// Local, honest analysis without an LLM: extractive summaries and counts
/// computed from the documents themselves. It never claims an LLM wrote it.
public enum PersonalDocLocalAnalyzer {
    public static func summarize(documents: [PersonalDocDocument], maxSentences: Int = 5) -> String {
        let text = documents.map { $0.markdownSource }.joined(separator: "\n")
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: ".!\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 24 }
        guard !sentences.isEmpty else { return "No document text to summarize." }
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 }
        var frequency: [String: Int] = [:]
        for word in words { frequency[word, default: 0] += 1 }
        let stopwords: Set<String> = ["with", "this", "that", "from", "have", "will", "when", "which", "about"]
        let scored = sentences.map { sentence -> (String, Int) in
            let sentenceWords = sentence.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            let score = sentenceWords.reduce(0) { $0 + (stopwords.contains($1) ? 0 : (frequency[$1] ?? 0)) }
            return (sentence, score)
        }
        let top = scored.sorted { $0.1 > $1.1 }.prefix(maxSentences).map { "- \($0.0)." }
        return "Local summary (\(documents.count) document(s), \(words.count) words):\n" + top.joined(separator: "\n")
    }

    public static func missingDocumentation(documents: [PersonalDocDocument]) -> String {
        let kinds = Set(documents.map { $0.moduleKind })
        let missing = PersonalDocModuleKind.allCases.filter { $0.archetype == .structured && !kinds.contains($0) }
        guard !missing.isEmpty else { return "Every structured module has at least one document." }
        return "Modules with no documents yet:\n" + missing.map { "- \($0.rawValue)" }.joined(separator: "\n")
    }

    public static func duplicateTitles(documents: [PersonalDocDocument]) -> String {
        var counts: [String: Int] = [:]
        for doc in documents { counts[doc.title.lowercased(), default: 0] += 1 }
        let dupes = counts.filter { $0.value > 1 }.sorted { $0.key < $1.key }
        guard !dupes.isEmpty else { return "No duplicate document titles found." }
        return "Duplicate titles:\n" + dupes.map { "- \"\($0.key)\" (\($0.value) documents)" }.joined(separator: "\n")
    }
}

/// The JSON-backed store for one project's personal documentation.
/// One file per collection under Application Support
/// `SwiftCode/PersonalDocs/<project-hash>/`; writes are atomic.
@Observable
@MainActor
public final class PersonalDocStore {
    public let projectID: UUID
    public let projectURL: URL
    public var textProvider: (any PersonalDocTextProvider)?

    public private(set) var documents: [PersonalDocDocument] = []
    public private(set) var templates: [PersonalDocTemplate] = []
    public private(set) var wikiPages: [PersonalDocWikiPage] = []
    public private(set) var versions: [PersonalDocVersion] = []
    public private(set) var relationships: [PersonalDocRelationship] = []
    public private(set) var attachments: [PersonalDocAttachment] = []
    public private(set) var smartCollections: [PersonalDocSmartCollection] = []
    public private(set) var insights: [PersonalDocAIInsight] = []
    public private(set) var events: [PersonalDocAnalyticsEvent] = []
    public private(set) var whiteboards: [PersonalDocWhiteboard] = []
    public private(set) var snippets: [PersonalDocSnippet] = []
    public private(set) var snapshots: [PersonalDocSnapshot] = []

    /// Word -> document IDs, rebuilt on load and on every mutation.
    private var index: [String: Set<UUID>] = [:]

    public var storeDirectory: URL {
        if IDEProcess.isTestProcess {
            let hash = abs(projectURL.path.hashValue)
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-personaldocs-tests-\(ProcessInfo.processInfo.processIdentifier)-\(String(format: "%012x", hash))", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let hash = abs(projectURL.path.hashValue)
        return base.appendingPathComponent("SwiftCode/PersonalDocs/\(String(format: "%012x", hash))", isDirectory: true)
    }

    public init(projectID: UUID, projectURL: URL) {
        self.projectID = projectID
        self.projectURL = projectURL
        loadAll()
        if templates.isEmpty { seedDefaultTemplates() }
    }

    // MARK: - Persistence

    private func fileURL(_ name: String) -> URL { storeDirectory.appendingPathComponent(name) }

    private func load<T: Decodable>(_ name: String) -> [T] {
        guard let data = try? Data(contentsOf: fileURL(name)) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    private func save<T: Encodable>(_ value: [T], _ name: String) {
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(name), options: .atomic)
    }

    private func loadAll() {
        documents = load("documents.json")
        templates = load("templates.json")
        wikiPages = load("wiki.json")
        versions = load("versions.json")
        relationships = load("relationships.json")
        attachments = load("attachments.json")
        smartCollections = load("collections.json")
        insights = load("insights.json")
        events = load("analytics.json")
        whiteboards = load("whiteboards.json")
        snippets = load("snippets.json")
        snapshots = load("snapshots.json")
        rebuildIndex()
    }

    private func persistDocuments() { save(documents, "documents.json"); rebuildIndex() }

    private func rebuildIndex() {
        var fresh: [String: Set<UUID>] = [:]
        for doc in documents {
            let text = (doc.title + " " + doc.markdownSource + " " + doc.tags.joined(separator: " ")).lowercased()
            for word in text.components(separatedBy: CharacterSet.alphanumerics.inverted) where word.count > 2 {
                fresh[word, default: []].insert(doc.id)
            }
        }
        index = fresh
    }

    // MARK: - Documents

    public func fetchDocuments(for kind: PersonalDocModuleKind? = nil) -> [PersonalDocDocument] {
        let list = documents.filter { !$0.archived && (kind == nil || $0.moduleKind == kind) }
        return list.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    public func fetchDocument(id: UUID) -> PersonalDocDocument? { documents.first { $0.id == id } }

    @discardableResult
    public func createDocument(title: String, kind: PersonalDocModuleKind, markdown: String = "", tags: [String] = []) -> PersonalDocDocument {
        let doc = PersonalDocDocument(projectID: projectID, archetype: kind.archetype.rawValue, moduleKind: kind, title: title, markdownSource: markdown, tags: tags)
        documents.append(doc)
        persistDocuments()
        return doc
    }

    public func updateDocument(_ doc: PersonalDocDocument) {
        guard let idx = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        recordVersion(for: documents[idx])
        var updated = doc
        updated.updatedAt = Date()
        documents[idx] = updated
        persistDocuments()
    }

    public func deleteDocument(_ doc: PersonalDocDocument) {
        documents.removeAll { $0.id == doc.id }
        versions.removeAll { $0.documentID == doc.id }
        save(versions, "versions.json")
        persistDocuments()
    }

    public func fetchAllTags() -> [String] {
        Array(Set(documents.flatMap { $0.tags })).sorted()
    }

    public func addTag(_ tag: String, to doc: PersonalDocDocument) {
        guard var updated = fetchDocument(id: doc.id), !updated.tags.contains(tag) else { return }
        updated.tags.append(tag)
        updateDocument(updated)
    }

    public func removeTag(_ tag: String, from doc: PersonalDocDocument) {
        guard var updated = fetchDocument(id: doc.id) else { return }
        updated.tags.removeAll { $0 == tag }
        updateDocument(updated)
    }

    // MARK: - Journal / planning

    public func getOrCreateDailyNote(for date: Date = Date()) throws -> PersonalDocDocument {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let title = formatter.string(from: date)
        if let existing = documents.first(where: { $0.moduleKind == .dailyNotes && $0.title == title }) { return existing }
        return createDocument(title: title, kind: .dailyNotes, markdown: "# \(title)\n\n")
    }

    public func fetchPlanningItems(for kind: PersonalDocModuleKind) -> [PersonalDocDocument] {
        fetchDocuments(for: kind)
    }

    @discardableResult
    public func createPlanningItem(title: String, kind: PersonalDocModuleKind, status: String, priority: String) -> PersonalDocDocument {
        var doc = createDocument(title: title, kind: kind)
        doc.status = status
        doc.priority = priority
        updateDocument(doc)
        return fetchDocument(id: doc.id) ?? doc
    }

    // MARK: - Search

    public func search(query: String) -> [PersonalDocSearchResult] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let words = needle.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        var scores: [UUID: Int] = [:]
        for word in words {
            for id in index[word] ?? [] { scores[id, default: 0] += 1 }
        }
        // Title matches count double.
        for doc in documents where doc.title.lowercased().contains(needle) { scores[doc.id, default: 0] += 2 }
        return scores.compactMap { (id, score) -> PersonalDocSearchResult? in
            guard let doc = fetchDocument(id: id) else { return nil }
            let body = doc.markdownSource
            let snippet: String
            if let range = body.lowercased().range(of: needle) {
                let start = body.index(range.lowerBound, offsetBy: -min(40, body.distance(from: body.startIndex, to: range.lowerBound)))
                let end = body.index(range.upperBound, offsetBy: min(80, body.distance(from: range.upperBound, to: body.endIndex)))
                snippet = String(body[start..<end])
            } else {
                snippet = String(body.prefix(120))
            }
            return PersonalDocSearchResult(document: doc, score: score, snippet: snippet)
        }.sorted { $0.score > $1.score }
    }

    // MARK: - Templates

    public func fetchTemplates(for kind: PersonalDocModuleKind) -> [PersonalDocTemplate] {
        templates.filter { $0.moduleKind == kind || $0.projectID == nil }
    }

    @discardableResult
    public func createTemplate(title: String, description: String, markdown: String, for kind: PersonalDocModuleKind, isGlobal: Bool = false) -> PersonalDocTemplate {
        let template = PersonalDocTemplate(projectID: isGlobal ? nil : projectID, moduleKind: kind, title: title, descriptionText: description, markdownSource: markdown)
        templates.append(template)
        save(templates, "templates.json")
        return template
    }

    public func seedDefaultTemplates() {
        let defaults: [(PersonalDocModuleKind, String, String, String)] = [
            (.meetingNotes, "Meeting Notes", "Attendees, agenda, decisions and action items.", "# Meeting Notes\n\n**Date:** \n**Attendees:** \n\n## Agenda\n\n## Decisions\n\n## Action Items\n"),
            (.bugDatabase, "Bug Report", "Reproduction steps, severity and stack trace.", "# Bug Report\n\n**Severity:** \n**Status:** Open\n\n## Reproduction Steps\n\n## Expected\n\n## Actual\n"),
            (.userStory, "User Story", "As a user, I want… so that…", "# User Story\n\n**As a** \n**I want** \n**So that** \n\n## Acceptance Criteria\n\n"),
            (.technicalSpecification, "Technical Specification", "Goals, design and open questions.", "# Technical Specification\n\n## Goals\n\n## Design\n\n## Open Questions\n"),
            (.releaseChecklist, "Release Checklist", "Pre-release verification steps.", "# Release Checklist\n\n- [ ] Version bumped\n- [ ] Changelog updated\n- [ ] Tests pass\n- [ ] Archive built\n"),
            (.dailyNotes, "Daily Note", "A dated journal entry.", "# Daily Note\n\n## Done\n\n## Doing\n\n## Notes\n"),
        ]
        for (kind, title, description, markdown) in defaults {
            createTemplate(title: title, description: description, markdown: markdown, for: kind, isGlobal: true)
        }
    }

    // MARK: - Version history

    public func recordVersion(for doc: PersonalDocDocument) {
        let version = PersonalDocVersion(projectID: projectID, documentID: doc.id, titleSnapshot: doc.title, markdownSnapshot: doc.markdownSource)
        versions.append(version)
        save(versions, "versions.json")
    }

    public func fetchVersions(for documentID: UUID) -> [PersonalDocVersion] {
        versions.filter { $0.documentID == documentID }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Wiki / relationships / attachments

    public func fetchWikiPages() -> [PersonalDocWikiPage] {
        wikiPages.sorted { $0.title < $1.title }
    }

    @discardableResult
    public func createOrUpdateWikiPage(title: String, content: String) -> PersonalDocWikiPage {
        if var page = wikiPages.first(where: { $0.title.lowercased() == title.lowercased() }) {
            page.markdownSource = content
            page.lastUpdated = Date()
            wikiPages.removeAll { $0.id == page.id }
            wikiPages.append(page)
            save(wikiPages, "wiki.json")
            return page
        }
        let page = PersonalDocWikiPage(projectID: projectID, title: title, markdownSource: content)
        wikiPages.append(page)
        save(wikiPages, "wiki.json")
        return page
    }

    public func fetchRelationships(for sourceDocumentID: UUID) -> [PersonalDocRelationship] {
        relationships.filter { $0.sourceDocumentID == sourceDocumentID }
    }

    public func addLink(sourceID: UUID, targetType: String, targetIdentifier: String, targetName: String) {
        let rel = PersonalDocRelationship(projectID: projectID, sourceDocumentID: sourceID, targetType: targetType, targetIdentifier: targetIdentifier, targetName: targetName)
        relationships.append(rel)
        save(relationships, "relationships.json")
    }

    public func removeLink(_ rel: PersonalDocRelationship) {
        relationships.removeAll { $0.id == rel.id }
        save(relationships, "relationships.json")
    }

    @discardableResult
    public func saveAttachment(fileURL: URL, name: String) throws -> PersonalDocAttachment {
        let dir = storeDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: fileURL, to: dest)
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let record = PersonalDocAttachment(
            projectID: projectID, relativePath: "Attachments/\(name)", originalFileName: name,
            mimeType: "application/octet-stream", fileSize: (attrs[.size] as? Int64) ?? 0)
        attachments.append(record)
        save(attachments, "attachments.json")
        return record
    }

    public func attachmentURL(for record: PersonalDocAttachment) -> URL {
        storeDirectory.appendingPathComponent(record.relativePath)
    }

    // MARK: - Dashboard / analytics

    public struct DashboardSnapshot: Sendable {
        public let totalDocuments: Int
        public let totalTasks: Int
        public let completedTasks: Int
        public let recentDocuments: [PersonalDocDocument]
    }

    public func dashboardSnapshot() -> DashboardSnapshot {
        let tasks = documents.filter { $0.moduleKind.archetype == .structured }
        let completed = tasks.filter { ($0.status ?? "").lowercased() == "done" || ($0.status ?? "").lowercased() == "completed" }.count
        let recent = documents.sorted { $0.updatedAt > $1.updatedAt }.prefix(5).map { $0 }
        return DashboardSnapshot(totalDocuments: documents.count, totalTasks: tasks.count, completedTasks: completed, recentDocuments: Array(recent))
    }

    public func logEvent(_ name: String, metadata: [String: String]? = nil) {
        events.append(PersonalDocAnalyticsEvent(projectID: projectID, eventName: name, metadata: metadata))
        save(events, "analytics.json")
    }

    public func fetchEventCount(named name: String) -> Int {
        events.filter { $0.eventName == name }.count
    }

    // MARK: - Ecosystem: whiteboards / snippets / snapshots / timeline

    public func fetchWhiteboards() -> [PersonalDocWhiteboard] { whiteboards.sorted { $0.updatedAt > $1.updatedAt } }
    @discardableResult
    public func createWhiteboard(title: String) -> PersonalDocWhiteboard {
        let board = PersonalDocWhiteboard(projectID: projectID, title: title)
        whiteboards.append(board); save(whiteboards, "whiteboards.json"); return board
    }
    public func updateWhiteboard(_ record: PersonalDocWhiteboard) {
        guard let idx = whiteboards.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = record; updated.updatedAt = Date(); whiteboards[idx] = updated
        save(whiteboards, "whiteboards.json")
    }
    public func deleteWhiteboard(_ record: PersonalDocWhiteboard) {
        whiteboards.removeAll { $0.id == record.id }; save(whiteboards, "whiteboards.json")
    }

    public func fetchSnippets() -> [PersonalDocSnippet] { snippets.sorted { $0.title < $1.title } }
    @discardableResult
    public func createSnippet(title: String, code: String, language: String, category: String, tags: [String] = []) -> PersonalDocSnippet {
        let snippet = PersonalDocSnippet(projectID: projectID, title: title, code: code, language: language, category: category, tags: tags)
        snippets.append(snippet); save(snippets, "snippets.json"); return snippet
    }
    public func updateSnippet(_ record: PersonalDocSnippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = record
        updated.versionHistory.append(record.code)
        snippets[idx] = updated
        save(snippets, "snippets.json")
    }
    public func deleteSnippet(_ record: PersonalDocSnippet) {
        snippets.removeAll { $0.id == record.id }; save(snippets, "snippets.json")
    }

    public func fetchSnapshots() -> [PersonalDocSnapshot] { snapshots.sorted { $0.createdAt > $1.createdAt } }
    @discardableResult
    public func createSnapshot(title: String, description: String) -> PersonalDocSnapshot {
        // Full content at capture time (Legacy `SnapshotManager.createSnapshot`):
        // the snapshot stores the records themselves, not just their IDs,
        // so a later restore can recover content that was edited or deleted.
        let snapshot = PersonalDocSnapshot(
            projectID: projectID, title: title, description: description,
            documentIDs: documents.map { $0.id }, whiteboardIDs: whiteboards.map { $0.id }, snippetIDs: snippets.map { $0.id },
            documentsJSON: encoded(documents), whiteboardsJSON: encoded(whiteboards), snippetsJSON: encoded(snippets))
        snapshots.append(snapshot); save(snapshots, "snapshots.json"); return snapshot
    }
    public func restoreSnapshot(_ snapshot: PersonalDocSnapshot) {
        // Full-content restore (Legacy `SnapshotManager.restoreSnapshot`):
        // the captured records replace the live ones, so edited or deleted
        // content comes back. Snapshots written before content payloads
        // existed carry `"[]"` and fall back to the old ID-only behaviour
        // (archive everything not in the snapshot, un-archive what it holds).
        let restoredDocs = decoded([PersonalDocDocument].self, from: snapshot.documentsJSON)
        let restoredBoards = decoded([PersonalDocWhiteboard].self, from: snapshot.whiteboardsJSON)
        let restoredSnippets = decoded([PersonalDocSnippet].self, from: snapshot.snippetsJSON)
        if restoredDocs == nil && restoredBoards == nil && restoredSnippets == nil {
            for idx in documents.indices {
                documents[idx].archived = !snapshot.documentIDs.contains(documents[idx].id)
            }
            persistDocuments()
            return
        }
        if let docs = restoredDocs {
            documents = docs
            persistDocuments()
        }
        if let boards = restoredBoards {
            whiteboards = boards
            save(whiteboards, "whiteboards.json")
        }
        if let snippets = restoredSnippets {
            self.snippets = snippets
            save(self.snippets, "snippets.json")
        }
    }

    /// Duplicates a snapshot under a new id (the "Copy" action): all payloads
    /// are copied verbatim, so the copy restores exactly what the original
    /// captured. Defaults to "<title> Copy".
    @discardableResult
    public func duplicateSnapshot(_ snapshot: PersonalDocSnapshot, title: String? = nil) -> PersonalDocSnapshot {
        let copy = PersonalDocSnapshot(
            projectID: snapshot.projectID, title: title ?? "\(snapshot.title) Copy",
            description: snapshot.description, documentIDs: snapshot.documentIDs,
            whiteboardIDs: snapshot.whiteboardIDs, snippetIDs: snapshot.snippetIDs,
            documentsJSON: snapshot.documentsJSON, whiteboardsJSON: snapshot.whiteboardsJSON,
            snippetsJSON: snapshot.snippetsJSON)
        snapshots.append(copy); save(snapshots, "snapshots.json"); return copy
    }

    /// Replaces a snapshot in place (e.g. after a rename). No-op when the id
    /// is not in the store.
    public func updateSnapshot(_ snapshot: PersonalDocSnapshot) {
        guard let idx = snapshots.firstIndex(where: { $0.id == snapshot.id }) else { return }
        snapshots[idx] = snapshot; save(snapshots, "snapshots.json")
    }

    /// Removes a snapshot. No-op when the id is not in the store.
    public func deleteSnapshot(_ snapshot: PersonalDocSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }; save(snapshots, "snapshots.json")
    }

    /// Removes a wiki page. No-op when the id is not in the store.
    public func deleteWikiPage(_ page: PersonalDocWikiPage) {
        wikiPages.removeAll { $0.id == page.id }; save(wikiPages, "wiki.json")
    }

    /// Encodes records as the JSON payload a snapshot stores (`"[]"` when
    /// encoding fails, so a snapshot is never lost to a codec error).
    private func encoded<T: Encodable>(_ value: [T]) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    /// Decodes a snapshot payload; nil when the payload is absent or corrupt
    /// (the caller falls back to ID-only behaviour).
    private func decoded<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    public func fetchTimeline() -> [PersonalDocTimelineItem] {
        var items: [PersonalDocTimelineItem] = documents.map {
            PersonalDocTimelineItem(title: $0.title, detail: $0.moduleKind.rawValue, category: "document", date: $0.updatedAt, tags: $0.tags)
        }
        items += whiteboards.map { PersonalDocTimelineItem(title: $0.title, detail: "Whiteboard", category: "whiteboard", date: $0.updatedAt) }
        items += snippets.map { PersonalDocTimelineItem(title: $0.title, detail: $0.language, category: "snippet", date: $0.createdAt) }
        items += insights.map { PersonalDocTimelineItem(title: $0.kind, detail: "AI insight", category: "ai", date: $0.generatedAt) }
        return items.sorted { $0.date > $1.date }
    }

    // MARK: - Export / import

    public func exportToMarkdown(document: PersonalDocDocument, destinationURL: URL) throws {
        let text = "# \(document.title)\n\n\(document.markdownSource)\n"
        try text.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    public func exportToHTML(document: PersonalDocDocument, destinationURL: URL) throws {
        let escaped = document.markdownSource
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>\n")
        let html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(document.title)</title></head><body><h1>\(document.title)</h1><p>\(escaped)</p></body></html>"
        try html.write(to: destinationURL, atomically: true, encoding: .utf8)
    }

    public func importMarkdown(from url: URL) throws -> (title: String, content: String) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let title = lines.first(where: { $0.hasPrefix("# ") })?.dropFirst(2).trimmingCharacters(in: .whitespaces) ?? url.deletingPathExtension().lastPathComponent
        return (String(title), text)
    }

    // MARK: - AI analysis

    public enum PersonalDocAnalysisKind: String, Sendable, CaseIterable {
        case dailySummary = "Daily Summary"
        case weeklySummary = "Weekly Summary"
        case missingDocs = "Missing Documentation"
        case duplicateDocs = "Duplicate Ideas Detection"
        case knowledgeGaps = "Knowledge Gaps Analysis"
    }

    public func analyze(kind: PersonalDocAnalysisKind) async throws -> String {
        let docs = documents
        if let provider = textProvider {
            let context = docs.map { "## \($0.title)\n\($0.markdownSource)" }.joined(separator: "\n\n")
            let prompt = "You are a senior documentation and code quality analyzer. Review the following project documents context and generate a professional, constructive \(kind.rawValue) report as a markdown document.\n\n\(context)"
            let report = try await provider.generate(prompt: prompt)
            let insight = PersonalDocAIInsight(projectID: projectID, kind: kind.rawValue, sourceDocumentIDs: docs.map { $0.id }, content: report)
            insights.append(insight)
            save(insights, "insights.json")
            return report
        }
        switch kind {
        case .dailySummary, .weeklySummary:
            return PersonalDocLocalAnalyzer.summarize(documents: docs)
        case .missingDocs:
            return PersonalDocLocalAnalyzer.missingDocumentation(documents: docs)
        case .duplicateDocs:
            return PersonalDocLocalAnalyzer.duplicateTitles(documents: docs)
        case .knowledgeGaps:
            let missing = PersonalDocLocalAnalyzer.missingDocumentation(documents: docs)
            let tags = fetchAllTags()
            return missing + "\n\nTags in use (\(tags.count)): " + tags.joined(separator: ", ")
        }
    }
}

/// Navigation state for the Personal Documentation window
/// (Legacy `PersonalDocumentationCoordinator` + `WorkspaceState`).
@Observable
@MainActor
public final class PersonalDocumentationCoordinator {
    public var selectedModuleKind: PersonalDocModuleKind? = .dashboard
    public var selectedDocumentID: UUID?
    public var selectedWikiPageID: UUID?
    public var selectedWhiteboardID: UUID?
    public var selectedSnippetID: UUID?
    public var selectedSnapshotID: UUID?
    public var searchQuery: String = ""
    public var searchActive: Bool = false
    public var showLivePreview: Bool = true
    public var showSidebar: Bool = true

    public let store: PersonalDocStore

    /// Live manager adapters over the store (Legacy exposed these as separate
    /// per-area sub-stores: `coordinator.documents/.whiteboards/.snippets/
    /// .snapshots/.timeline/.intelligence/.relationships`). The managers are
    /// thin wrappers that preserve the Legacy call sites; the store owns the
    /// data. Created on access — they hold no state beyond the store.
    public var whiteboards: WhiteboardManager { WhiteboardManager(store: store) }
    public var snippets: SnippetManager { SnippetManager(store: store) }
    public var snapshots: SnapshotManager { SnapshotManager(store: store) }
    public var timeline: EcosystemTimelineManager { EcosystemTimelineManager(store: store) }
    public var intelligence: IntelligenceManager { IntelligenceManager(store: store) }
    public var documents: PersonalDocDocumentManager { PersonalDocDocumentManager(store: store) }
    public var relationships: PersonalDocRelationshipManager { PersonalDocRelationshipManager(store: store) }

    public init(store: PersonalDocStore) {
        self.store = store
    }

    public func navigate(to module: PersonalDocModuleKind) {
        selectedModuleKind = module
        selectedDocumentID = nil
        searchActive = false
    }

    public func selectDocument(_ id: UUID) {
        selectedDocumentID = id
    }
}

/// Throwing adapter over `PersonalDocStore` document CRUD, preserving the
/// Legacy `DocumentManager` call shape (`coordinator.documents.*`) used by the
/// Personal Documentation views. The store itself is non-throwing; the
/// `throws` here exists only so existing `try?`/`try` call sites keep working.
public final class PersonalDocDocumentManager {
    private let store: PersonalDocStore
    public init(store: PersonalDocStore) { self.store = store }
    public func fetchDocuments() throws -> [PersonalDocDocument] { store.fetchDocuments() }
    public func fetchDocument(id: UUID) throws -> PersonalDocDocument? { store.fetchDocument(id: id) }
    public func createDocument(title: String, kind: PersonalDocModuleKind, markdown: String = "", tags: [String] = []) throws -> PersonalDocDocument {
        store.createDocument(title: title, kind: kind, markdown: markdown, tags: tags)
    }
    public func updateDocument(_ doc: PersonalDocDocument) throws { store.updateDocument(doc) }
    public func deleteDocument(_ doc: PersonalDocDocument) throws { store.deleteDocument(doc) }
}

/// Throwing adapter over `PersonalDocStore` relationship CRUD, preserving the
/// Legacy call shape (`coordinator.relationships.*`).
public final class PersonalDocRelationshipManager {
    private let store: PersonalDocStore
    public init(store: PersonalDocStore) { self.store = store }
    public func fetchRelationships(for sourceDocumentID: UUID) throws -> [PersonalDocRelationship] {
        store.fetchRelationships(for: sourceDocumentID)
    }
    public func addLink(sourceID: UUID, targetType: String, targetIdentifier: String, targetName: String) throws {
        store.addLink(sourceID: sourceID, targetType: targetType, targetIdentifier: targetIdentifier, targetName: targetName)
    }
    public func removeLink(_ rel: PersonalDocRelationship) throws { store.removeLink(rel) }
}
