import Foundation
import SwiftUI

public enum Archetype: String, Sendable, Codable {
    case freeform = "Freeform Document"
    case structured = "Structured Record"
    case generated = "Generated/Derived Document"
    case container = "Container/Organizer"
}

public enum ModuleKind: String, Sendable, Codable, CaseIterable, Identifiable {
    // A. Freeform Document
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

    // B. Structured Record
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

    // C. Generated/Derived Document
    case projectWiki = "Project Wiki"
    case dashboard = "Dashboard"
    case architectureDecisions = "Architecture Decisions"
    case aiInsights = "AI Insights"

    // D. Container/Organizer
    case smartCollections = "Smart Collections"
    case favorites = "Favorites"
    case archivedDocuments = "Archived Documents"
    case templates = "Templates"
    case bookmarks = "Bookmarks"
    case attachments = "Attachments"
    case images = "Images"
    case referenceLibrary = "Reference Library"

    // E. Advanced Ecosystem Extensions
    case knowledgeGraph = "Knowledge Graph"
    case timeline = "Project Timeline"
    case analytics = "Project Analytics"
    case intelligence = "Project Intelligence"
    case whiteboards = "Advanced Whiteboards"
    case snippets = "Snippet Workspace"
    case snapshots = "Project Snapshots"

    public var id: String { rawValue }

    public var archetype: Archetype {
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

        case .projectWiki, .dashboard, .architectureDecisions, .aiInsights:
            return .generated

        case .smartCollections, .favorites, .archivedDocuments, .templates, .bookmarks,
             .attachments, .images, .referenceLibrary:
            return .container

        case .knowledgeGraph, .timeline, .analytics, .intelligence, .whiteboards, .snippets, .snapshots:
            return .generated
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
