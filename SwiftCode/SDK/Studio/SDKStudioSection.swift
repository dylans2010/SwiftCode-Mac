import Foundation

// MARK: - SDKStudioSection
//
// The Studio sections (spec §13.3). Raw values are the exact display
// names; the `Identifiable` conformance (id = rawValue) lets
// `SDKStudioView` drive a `NavigationSplitView` sidebar selection directly
// without an adapter layer.
//
// The `codeEditor` case is the documented migration from
// `SDKStudioCodeEditorSection`: now that `SDKCodeEditorShellView` exists,
// the Code Editor is a first-class section. The descriptor struct is kept
// for string-id compatibility (see its file).

public enum SDKStudioSection: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case extensions = "Extensions"
    case apiKeys = "API Keys"
    case security = "Security"
    case logs = "Logs"
    case codeEditor = "Code Editor"
    case installedExtensions = "Installed"
    case assistAccess = "Assist Access"

    public var id: String { rawValue }

    /// SF Symbol shown next to the section title in the Studio sidebar.
    public var systemImage: String {
        switch self {
        case .projects:
            return "folder"
        case .extensions:
            return "puzzlepiece.extension"
        case .apiKeys:
            return "key"
        case .security:
            return "lock.shield"
        case .logs:
            return "doc.text"
        case .codeEditor:
            return "chevron.left.forwardslash.chevron.right"
        case .installedExtensions:
            return "app.badge"
        case .assistAccess:
            return "person.badge.key"
        }
    }
}
