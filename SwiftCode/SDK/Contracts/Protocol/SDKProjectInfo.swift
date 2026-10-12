import Foundation

// MARK: - SDKProjectInfo
//
// Public data contract for the SwiftCode project/workspace surface
// (spec §6.2 `ProjectAPI.getCurrent()`, architecture doc §2 `project.read`).
//
// Safe metadata only: identity, display name, and the project root path.
// Never carries file contents, credentials, or internal model state.
//
// Nullability contract (spec §6.3): `ProjectAPI.getCurrent()` MAY return
// null when no project is open. That optionality is modeled at the API
// layer (`SDKProjectInfo?`), NOT here — this struct always describes a
// real, open project.

public struct SDKProjectInfo: Codable, Sendable {
    /// Stable host-assigned project identifier (opaque to extensions).
    public let id: String

    /// Human-readable project display name.
    public let name: String

    /// Absolute filesystem path of the project root on the host machine.
    /// Scoped to the open project; extensions must not escape it.
    public let rootPath: String

    /// Whether the project is currently open in the host.
    /// Always `true` for values produced by `getCurrent()`; present so the
    /// contract stays stable if batch/list APIs are added later.
    public let isOpen: Bool

    public init(id: String, name: String, rootPath: String, isOpen: Bool = true) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.isOpen = isOpen
    }
}
