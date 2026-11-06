// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Models/AppSettings.swift — the five standalone model types only
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeAssistant/Models/LegacyAppSettingsModels.swift.
//
// Re-verified against current Legacy and current main by migration
// subagent A5: the five types below are verbatim Legacy (only `public`
// added) and do NOT exist anywhere in main — the full-symbol-diff
// "covered" claim for them was computed against the dropped batch-2 tree
// (commit 469be64d, which first staged this file), not main. The
// `AppSettings` singleton itself is NOT in this file; it is ported in
// `AppSettings.swift` in this directory (see that file's header for why
// the singleton is restored rather than left dissolved).
//
// One change over the batch-2 staging: `Sendable` is added to all five
// types. They are value types with Sendable members, and `AppSettings`
// (an `@Observable ... : Sendable` class) stores them, so the conformance
// is required for the class to be Sendable.

import Foundation

// MARK: - Saved Repository Model

public struct SavedRepository: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var owner: String
    public var repositoryURL: String
    public var defaultBranch: String
    public var localProjectPath: String?

    public init(id: UUID = UUID(), name: String, owner: String, repositoryURL: String, defaultBranch: String = "main", localProjectPath: String? = nil) {
        self.id = id
        self.name = name
        self.owner = owner
        self.repositoryURL = repositoryURL
        self.defaultBranch = defaultBranch
        self.localProjectPath = localProjectPath
    }
}

// MARK: - Dashboard Layout

public enum DashboardLayout: String, Codable, CaseIterable, Sendable {
    case grid = "Grid"
    case list = "List"
}

public enum DashboardSortOrder: String, Codable, CaseIterable, Sendable {
    case name = "Name"
    case lastOpened = "Last Opened"
    case creationDate = "Creation Date"
}

public enum FileNavigatorLayoutStyle: String, Codable, CaseIterable, Sendable {
    case compact = "Compact"
    case expanded = "Expanded"
}

public enum FileNavigatorAnimationStyle: String, Codable, CaseIterable, Sendable {
    case easeInOut = "Ease In/Out"
    case spring = "Spring"
    case bouncy = "Bouncy"
}
