import Foundation

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
