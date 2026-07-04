import SwiftUI

struct BuildToolbarView: ToolbarContent {
    @State var viewModel: BuildViewModel
    let projectURL: URL

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: {
                Task {
                    await viewModel.build(projectURL: projectURL, scheme: "SwiftCode")
                }
            }) {
                Label("Build", systemImage: "play.fill")
            }
            .disabled(viewModel.isBuilding)

            Button(action: {
                // In a real app, we'd cancel the task
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!viewModel.isBuilding)

            if viewModel.isBuilding {
                ProgressView().controlSize(.small)
            }
        }
    }
}
