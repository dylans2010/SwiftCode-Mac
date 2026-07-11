import SwiftUI

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                Task {
                    // Automatically open XcodeBuildLogView
                    NotificationCenter.default.post(
                        name: .toolbarToolActivated,
                        object: nil,
                        userInfo: ["toolID": "xcode_build_logs"]
                    )
                    // Trigger build in background
                    await buildManager.runBuild(projectURL: projectURL, scheme: "SwiftCode")
                }
            }) {
                Label("Build", systemImage: "play.fill")
            }
            .disabled(buildManager.isBuilding)
            .help("Run Xcodebuild on active project")

            Button(action: {
                buildManager.cancelBuild()
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!buildManager.isBuilding)
            .help("Stop active Xcodebuild run")

            if buildManager.isBuilding {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
