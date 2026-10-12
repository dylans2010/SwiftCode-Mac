import Foundation

// MARK: - SDKStudioSection
//
// The four Studio sections (spec §13.3). Raw values are the exact display
// names; the `Identifiable` conformance (id = rawValue) lets
// `SDKStudioView` drive a `NavigationSplitView` sidebar selection directly
// without an adapter layer.

public enum SDKStudioSection: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case extensions = "Extensions"
    case apiKeys = "API Keys"
    case logs = "Logs"

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
        case .logs:
            return "doc.text"
        }
    }
}
