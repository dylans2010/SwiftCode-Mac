import SwiftUI

struct GitCloneSheetView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var remoteURL = ""
    @State private var isCloning = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Clone Repository").font(.headline)
            TextField("Remote URL", text: $remoteURL)
            if isCloning {
                ProgressView("Cloning...")
            }
            HStack {
                Button("Cancel") { dismiss() }
                Button("Clone") {
                    clone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(remoteURL.isEmpty || isCloning)
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func clone() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Select clone destination"

        if panel.runModal() == .OK, let url = panel.url {
            isCloning = true
            Task {
                do {
                    let remote = URL(string: remoteURL)!
                    let destination = url.appendingPathComponent(remote.deletingPathExtension().lastPathComponent)
                    let token = try? await KeychainService.shared.get(account: "github-pat")
                    try await GitService.shared.clone(remoteURL: remote, destinationURL: destination, token: token)
                    await viewModel.importProject(url: destination)
                    dismiss()
                } catch {
                    LoggingTool.error("Clone failed: \(error)")
                }
                isCloning = false
            }
        }
    }
}
