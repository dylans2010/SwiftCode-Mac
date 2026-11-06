import Foundation

public enum ExtensionCapabilityID: String, Codable, Sendable, CaseIterable {
    case projectRead = "project.read"
    case workspaceRead = "workspace.read"
    case workspaceWrite = "workspace.write"
    case sourceControlRead = "source-control.read"
    case sourceControlWrite = "source-control.write"
    case buildExecute = "build.execute"
    case taskExecute = "task.execute"
    case networkRequest = "network.request"
    case uiContribute = "ui.contribute"
    case credentialsUse = "credentials.use"
    case useSecurity = "use.Security"
    case assistInvoke = "assist.invoke"
    case assistUI = "assist.ui"
    case assistHeadless = "assist.headless"
    case assistMainView = "assist.main"
    case dbExploreView = "db.ExploreView"
    case ciVisualWF = "ci.VisualWF"
    case sandboxView = "sandbox.view"
    case virtualizationView = "virtualization.view"
    case deployConsoleView = "deployConsole.view"
    case useSwiftCodeModel = "use.SwiftCodeModel"
    case terminalSandbox = "terminal.sandbox"
    case simulatorView = "simulator.view"
    case previewLive = "preview.live"
    case uiBuilderOpen = "uibuilder.open"
    case symbolsBrowse = "symbols.browse"
    case docsSearch = "docs.search"
    case dictionaryOpen = "dictionary.open"
    case deviceConnectOpen = "deviceconnect.open"
    case securityAddValue = "security.addValue"
    case securityHasValue = "security.hasValue"
    case securityListValueIDs = "security.listValueIDs"
    case securityDeleteValue = "security.deleteValue"
    case securityUseValue = "security.useValue"

    public var riskLevel: String {
        switch self {
        case .projectRead, .sourceControlRead, .docsSearch:
            return "low"
        case .workspaceRead, .uiContribute, .previewLive, .symbolsBrowse, .dictionaryOpen:
            return "medium"
        case .workspaceWrite, .sourceControlWrite, .buildExecute, .taskExecute, .networkRequest, .credentialsUse, .useSecurity, .securityAddValue, .securityDeleteValue, .securityUseValue:
            return "high"
        default:
            return "high"
        }
    }

    public var isGrantable: Bool {
        switch self {
        case .assistInvoke:
            return false // restricted deny-by-default
        default:
            return true
        }
    }
}

public struct ExtensionCapabilityDeclaration: Codable, Sendable, Equatable {
    public let id: String
    public let reason: String

    public init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }
}
