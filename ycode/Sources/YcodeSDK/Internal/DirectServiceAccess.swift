#if DEBUG
import Foundation

// MARK: - DirectServiceAccess
//
// Ported from Legacy `SwiftCode/SDK/Internal/DirectServiceAccess/DirectServiceAccess.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// DEBUG ONLY. Direct access to host services for SDK development and
// debugging — never compiled into release builds.
//
// ADAPTATION: Legacy exposed the app's in-process `GitService` actor
// here. Ycode has no in-process Git service — git goes through
// subprocesses (`SDKSourceControlAdapter`, `SDKSandboxedTerminal`) —
// so this file exposes the git executable URL instead. The pinned
// xcodebuild URL is preserved verbatim.

public enum DirectServiceAccess {
    /// Pinned xcodebuild executable (Legacy: `/usr/bin/xcodebuild`).
    public static let xcodeBuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    /// Git executable for direct subprocess use. There is no
    /// in-process `GitService` in Ycode; git is invoked through
    /// `SDKSourceControlAdapter` (status/diff) or the sandboxed
    /// terminal, never through a shared service object.
    public static let gitExecutableURL = URL(fileURLWithPath: "/usr/bin/git")
}
#endif
