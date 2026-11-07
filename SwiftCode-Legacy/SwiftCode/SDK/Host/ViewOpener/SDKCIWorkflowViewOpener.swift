import AppKit
import Foundation
import SwiftUI

@MainActor
public struct SDKCIWorkflowViewOpener {
    nonisolated public static let capabilityID: SDKCapabilityID = .ciVisualWF

    private static let window = SDKHostedWindow<WorkflowDashboardView>()

    public static func open() throws {
        let project = try SDKActiveProjectResolver.resolve()

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
