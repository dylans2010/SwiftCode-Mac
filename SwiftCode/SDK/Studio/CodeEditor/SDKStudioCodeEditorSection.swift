import Foundation

// MARK: - SDKStudioCodeEditorSection
//
// Studio shell descriptor for the Code Editor section.
//
// DESIGN DECISION (2026-10-12, contracts task): `SDKStudioSection` is
// technically extensible, but adding a `codeEditor` case right now would
// break the build — `SDKStudioView.studioDetailView(for:)` switches
// exhaustively over the enum, and the corresponding
// `SDKCodeEditorView` is a sibling task (this task is contracts-only).
// So the shell integration ships as this descriptor instead: same shape
// as a section (`id`, display title, SF Symbol) so the Studio shell can
// list and switch to it without touching the enum.
//
// MIGRATION PATH: when `SDKCodeEditorView` lands, add
// `case codeEditor = "Code Editor"` to `SDKStudioSection` (with the
// `"chevron.left.forwardslash.chevron.right"` system image), add the
// switch arm in `SDKStudioView`, and delete this descriptor. Until then,
// `SDKStudioWindowManager.shared.openStudio(section:)` keeps working
// unchanged for the four existing sections.

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
