import SwiftUI

struct ImportProjectSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Import Project").font(.headline)
            Button("Choose Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    Task {
                        await viewModel.importProject(url: url)
                        dismiss()
                    }
                }
            }
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}
