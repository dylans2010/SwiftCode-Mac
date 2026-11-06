import Foundation

// MARK: - SDKStudioCodeEditorSection
//
// Studio shell descriptor for the Code Editor section.
//
// MIGRATION STATUS (2026-10-12, shell task): the migration documented here
// is now COMPLETE — `SDKStudioSection` has a `case codeEditor = "Code
// Editor"` (system image `"chevron.left.forwardslash.chevron.right"`,
// reused verbatim from this descriptor) and `SDKStudioView` switches to
// `SDKCodeEditorShellView` for it. This struct is KEPT for compatibility:
// anything addressing the section by its stable string id ("codeEditor")
// keeps working unchanged.

public struct SDKStudioCodeEditorSection: Identifiable, Sendable, Hashable {
    /// Stable section identifier. Chosen to match the raw-value style of
    /// `SDKStudioSection` so the eventual enum case can reuse it verbatim.
    public var id: String { "codeEditor" }

    /// Display title, matching `SDKStudioSection.rawValue` conventions.
    public var title: String { "Code Editor" }

    /// SF Symbol, matching `SDKStudioSection.systemImage` conventions.
    public var systemImage: String { "chevron.left.forwardslash.chevron.right" }

    public init() {}
}
