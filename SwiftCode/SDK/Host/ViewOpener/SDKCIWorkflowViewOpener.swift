import AppKit
import Foundation
import SwiftUI

// MARK: - SDKCIWorkflowViewOpener
//
// View opener for capability `ci.VisualWF` ("CI / visual workflow").
//
// ## Which surface opens
// `WorkflowDashboardView` (public,
// SwiftCode/Views/GitHub/SwiftCodeWorkflows/WorkflowDashboardView.swift,
// `public init(project: Project, gitViewModel: GitViewModel)`), hosted in an
// SDK-owned `NSWindow` titled "CI / Visual Workflows".
//
// ## Why the dashboard and not ActionsView / WorkflowsCreateView
// The true GitHub-Actions CI views are `ActionsView` and
// `WorkflowsCreateView` (SwiftCode/Views/GitHub/), but both are `internal`
// and their only real presentation path is as sidebar destinations inside
// `SourceControlMainWrapper` (`SourceControlView.swift` switches on
// `SourceControlSidebarState.shared.selection`). Routing through that path
// would require modifying non-SDK app files, which is out of scope, so per
// the expansion plan the public, self-contained `WorkflowDashboardView` is
// the surface that opens. Caveat, stated plainly: the dashboard is the
// "SwiftCode Workflows" local-automation pipeline surface (Apple-Shortcuts-
// style local shell pipelines via `WorkflowManager.shared`), not the GitHub
// Actions run inspector — see the SDK audit notes for the distinction.
//
// ## Presentation
// The app's `WorkspaceView` sheet mechanism is driven by its internal
// `WorkspaceSheet` enum and cannot be extended from SDK code, so the opener
// uses the SDK-established window pattern (`SDKHostedWindow`, mirroring
// `SDKStudioWindowManager`): a real `NSWindow` + `NSHostingController`,
// raised with `makeKeyAndOrderFront`.
//
// ## Verification status
// Statically verified only — no Swift toolchain in this environment.
// Needs `xcodebuild` on Dylan's Mac: target membership of the new file,
// `WorkflowDashboardView` init signature, and a live open of the window.

@MainActor
public struct SDKCIWorkflowViewOpener {
    /// Capability this opener serves: `ci.VisualWF`.
    nonisolated public static let capabilityID: SDKCapabilityID = .ciVisualWF

    private static let window = SDKHostedWindow<WorkflowDashboardView>()

    /// Opens the CI / visual-workflows dashboard in its own window.
    /// - Throws: `SDKError` with code `.projectNotOpen` when no project is
    ///   open (the view requires a `Project`). Never a silent no-op.
    public static func open() throws {
        let project = try SDKActiveProjectResolver.resolve()

        // Same wiring the app itself uses (AppCommands.swift): a fresh
        // GitViewModel pointed at the project's directory.
        let gitViewModel = GitViewModel()
        gitViewModel.repositoryURL = project.directoryURL

        window.show(
            rootView: WorkflowDashboardView(project: project, gitViewModel: gitViewModel),
            title: "CI / Visual Workflows",
            size: NSSize(width: 1100, height: 700),
            autosaveName: "SDKCIWorkflowWindow",
            minSize: NSSize(width: 900, height: 600)
        )
    }
}
