import Foundation

// MARK: - SDKStudioSection
//
// The Studio sections (spec §13.3). Raw values are the exact display
// names; the `Identifiable` conformance (id = rawValue) lets
// `SDKStudioView` drive a `NavigationSplitView` sidebar selection directly
// without an adapter layer.

public enum SDKStudioSection: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case codeEditor = "Code Editor"
    case manifestEditor = "Manifest Editor"
    case extensions = "Extensions"
    case apiKeys = "API Keys"
    case security = "Security"
    case logs = "Logs"
    case installedExtensions = "Installed"
    case assistAccess = "Assist Access"
    case sdk = "SDK & Downloads"
    case shipExport = "Ship & Export"

    public var id: String { rawValue }

    /// SF Symbol shown next to the section title in the Studio sidebar.
    public var systemImage: String {
        switch self {
        case .projects:
            return "folder"
        case .codeEditor:
            return "chevron.left.forwardslash.chevron.right"
        case .manifestEditor:
            return "doc.badge.gearshape"
        case .extensions:
            return "puzzlepiece.extension"
        case .apiKeys:
            return "key"
        case .security:
            return "lock.shield"
        case .logs:
            return "doc.text"
        case .installedExtensions:
            return "app.badge"
        case .assistAccess:
            return "person.badge.key"
        case .sdk:
            return "shippingbox"
        case .shipExport:
            return "square.and.arrow.up"
        }
    }
}
