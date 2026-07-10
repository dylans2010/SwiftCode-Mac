import Foundation
import Observation

@Observable
@MainActor
public final class ProjectEditorCoordinator: Sendable {
    public static let shared = ProjectEditorCoordinator()

    public enum ProjectSection: String, CaseIterable, Identifiable, Sendable {
        case overview = "Project Overview"
        case general = "General"
        case identity = "Identity"
        case deployment = "Deployment"
        case buildSettings = "Build Settings"
        case buildRules = "Build Rules"
        case buildPhases = "Build Phases"
        case buildConfigurations = "Build Configurations"
        case targets = "Targets"
        case products = "Products"
        case packages = "Packages"
        case frameworks = "Frameworks"
        case dependencies = "Dependencies"
        case signingCapabilities = "Signing & Capabilities"
        case entitlements = "Entitlements"
        case infoPlist = "Info.plist"
        case assets = "Assets"
        case localization = "Localization"
        case resources = "Resources"
        case sourceFiles = "Source Files"
        case headers = "Headers"
        case swiftPackages = "Swift Packages"
        case warnings = "Warnings"
        case diagnostics = "Diagnostics"
        case search = "Search"
        case relationships = "Relationships"
        case projectStatistics = "Project Statistics"
        case metadata = "Metadata"
        case projectSummary = "Project Summary"
        case targetSummary = "Target Summary"
        case fileReferences = "File References"
        case groups = "Groups"
        case copyFiles = "Copy Files"
        case shellScripts = "Shell Scripts"
        case headerPhases = "Header Phases"
        case resourcesPhase = "Resources Phase"
        case frameworkPhase = "Framework Phase"
        case packageDependencies = "Package Dependencies"
        case projectInspector = "Project Inspector"
        case targetInspector = "Target Inspector"
        case buildLogs = "Build Logs"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .overview, .projectSummary: return "info.circle"
            case .general: return "slider.horizontal.3"
            case .identity: return "person.crop.square"
            case .deployment: return "play.circle"
            case .buildSettings: return "slider.horizontal.3"
            case .buildRules: return "list.bullet.rectangle"
            case .buildPhases, .headerPhases, .resourcesPhase, .frameworkPhase: return "shippingbox"
            case .buildConfigurations: return "gearshape"
            case .targets, .targetSummary: return "target"
            case .products: return "macpro.gen3"
            case .packages, .swiftPackages, .packageDependencies: return "shippingbox.fill"
            case .frameworks: return "square.stack.3d.up"
            case .dependencies: return "arrow.3.arrows.asymmetrical.trianglepath"
            case .signingCapabilities: return "key.fill"
            case .entitlements: return "lock.shield"
            case .infoPlist: return "list.bullet.rectangle.fill"
            case .assets: return "photo.on.rectangle"
            case .localization: return "globe"
            case .resources: return "doc.text"
            case .sourceFiles: return "doc.text.fill"
            case .headers: return "h.square"
            case .warnings: return "exclamationmark.triangle"
            case .diagnostics: return "waveform.path.ecg"
            case .search: return "magnifyingglass"
            case .relationships: return "arrow.up.and.down.and.sparkles"
            case .projectStatistics: return "chart.bar"
            case .metadata: return "doc.markup"
            case .fileReferences, .groups: return "folder"
            case .copyFiles: return "doc.on.doc"
            case .shellScripts: return "terminal"
            case .projectInspector, .targetInspector: return "sidebar.trailing"
            case .buildLogs: return "doc.text.magnifyingglass"
            }
        }
    }

    public var selectedTab: ProjectSection = .overview {
        didSet {
            recordNavigation(selectedTab)
        }
    }

    public var selectedTargetID: String?
    public var selectedFileID: String?
    public var selectedBuildPhaseID: String?
    public var selectedBuildRuleID: String?
    public var selectedPackageID: String?
    public var selectedResourceID: String?
    public var selectedInspectorID: String?
    public var selectedConfigurationID: String?
    public var selectedCapabilityID: String?
    public var selectedInfoPlistEntryKey: String?

    // Navigation persistence and restoration
    public var expandedDisclosureGroups: Set<String> = []
    public var scrollPosition: Double = 0.0
    public var searchState: String = ""

    // Navigation history
    private var history: [ProjectSection] = [.overview]
    private var historyIndex: Int = 0
    public var recentlyViewed: [ProjectSection] = [.overview]

    // Undo / Redo for routing state
    private struct RouteState: Equatable {
        let tab: ProjectSection
        let targetID: String?
        let fileID: String?
        let buildPhaseID: String?
        let buildRuleID: String?
        let packageID: String?
        let resourceID: String?
        let configurationID: String?
    }

    private var undoStack: [RouteState] = []
    private var redoStack: [RouteState] = []

    private var isRecordingHistory = true

    private func recordNavigation(_ section: ProjectSection) {
        guard isRecordingHistory else { return }

        // Remove forward history if we navigated to a new place
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }

        history.append(section)
        historyIndex = history.count - 1

        if !recentlyViewed.contains(section) {
            recentlyViewed.insert(section, at: 0)
            if recentlyViewed.count > 10 {
                recentlyViewed.removeLast()
            }
        }

        // Push current state to undo stack
        let state = RouteState(
            tab: section,
            targetID: selectedTargetID,
            fileID: selectedFileID,
            buildPhaseID: selectedBuildPhaseID,
            buildRuleID: selectedBuildRuleID,
            packageID: selectedPackageID,
            resourceID: selectedResourceID,
            configurationID: selectedConfigurationID
        )
        if undoStack.last != state {
            undoStack.append(state)
            if undoStack.count > 50 {
                undoStack.removeFirst()
            }
        }
        redoStack.removeAll()
    }

    public var canGoBack: Bool {
        historyIndex > 0
    }

    public var canGoForward: Bool {
        historyIndex < history.count - 1
    }

    public func goBack() {
        guard canGoBack else { return }
        isRecordingHistory = false
        historyIndex -= 1
        selectedTab = history[historyIndex]
        isRecordingHistory = true
    }

    public func goForward() {
        guard canGoForward else { return }
        isRecordingHistory = false
        historyIndex += 1
        selectedTab = history[historyIndex]
        isRecordingHistory = true
    }

    public var canUndo: Bool {
        undoStack.count > 1
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public func undo() {
        guard undoStack.count > 1 else { return }
        let current = undoStack.removeLast()
        redoStack.append(current)
        if let previous = undoStack.last {
            applyState(previous)
        }
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(next)
        applyState(next)
    }

    private func applyState(_ state: RouteState) {
        isRecordingHistory = false
        selectedTab = state.tab
        selectedTargetID = state.targetID
        selectedFileID = state.fileID
        selectedBuildPhaseID = state.buildPhaseID
        selectedBuildRuleID = state.buildRuleID
        selectedPackageID = state.packageID
        selectedResourceID = state.resourceID
        selectedConfigurationID = state.configurationID
        isRecordingHistory = true
    }
}
