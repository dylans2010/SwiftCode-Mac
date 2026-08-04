import SwiftUI

public struct SCVirtualizationView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                if let project = sessionStore.activeProject {
                    VirtualizationWindowManager.shared.showWindow(for: project)
                } else {
                    // Fallback to a professional workspace if none active
                    let fallbackProject = Project(name: "Virtualization Workspace")
                    VirtualizationWindowManager.shared.showWindow(for: fallbackProject)
                }
                dismiss()
            }
    }
}
