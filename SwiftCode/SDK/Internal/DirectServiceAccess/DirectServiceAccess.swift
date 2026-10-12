#if DEBUG

import Foundation

/// Direct handles to host services for the internal test harness and
/// Studio debug flows.
///
/// **INTERNAL DEVELOPMENT/TESTING ONLY.** These bindings bypass the
/// capability broker's normal permission checks and exist solely for the
/// DEBUG-only test harness and internal Studio debugging. They are
/// compiled only under `#if DEBUG` and are stripped from release builds —
/// extensions and release builds can never reach them.
public enum DirectServiceAccess {
    /// Direct handle to the app's source-control service.
    ///
    /// `GitService` is a `public actor` singleton living in the same app
    /// target, so this binding needs no import beyond the app module.
    /// Internal use only; the public `source-control.read` capability is
    /// enforced separately by the capability broker.
    public static var gitService: GitService {
        GitService.shared
    }

    /// Direct URL to the pinned Xcode build tool.
    ///
    /// Always `/usr/bin/xcodebuild` — never the user-overridable
    /// `xcodebuild_executable_path` preference. Internal use only.
    public static var xcodeBuildURL: URL {
        URL(fileURLWithPath: "/usr/bin/xcodebuild")
    }
}

#endif
