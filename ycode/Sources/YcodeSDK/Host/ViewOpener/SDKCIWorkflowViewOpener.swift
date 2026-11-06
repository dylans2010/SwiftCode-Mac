import Foundation

// MARK: - SDKCIWorkflowViewOpener
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKCIWorkflowViewOpener.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Opens the CI / visual workflow dashboard (`ci.VisualWF`) for the
// active project. Requires a project — `.projectNotOpen` otherwise.
//
// NOTE: this dashboard is the LOCAL-automation surface (visual
// workflows), not a GitHub Actions inspector. The dashboard view
// itself is owned by the host UI behind the `SDKViewHost` seam; this
// file owns only the view ID, the project requirement, and the
// registration.

public enum SDKCIWorkflowViewOpener {
    public static let viewID = "ci.VisualWF"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            // The project requirement is enforced here so the host
            // never opens the dashboard without a project.
            _ = try await SDKActiveProjectResolver.activeProjectRoot()
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
