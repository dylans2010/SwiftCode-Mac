import SwiftUI

struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL

    var body: some View {
        HStack {
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
