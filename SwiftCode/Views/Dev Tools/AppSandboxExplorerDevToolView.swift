import SwiftUI
import os.log

@Observable
@MainActor
final class AppSandboxExplorerViewModel {
    var files: [String] = []
    var currentDirectory: String = ""
    var errorMessage: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "AppSandboxExplorer")

    func loadSandboxFiles() {
        errorMessage = nil
        files = []

        let fileManager = FileManager.default
        let libraryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        guard let url = libraryURL else {
            errorMessage = "Unable to resolve Application Support directory URL."
            return
        }

        currentDirectory = url.path

        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            files = contents.map { $0.lastPathComponent }
            logger.info("Successfully loaded sandbox files from Application Support")
        } catch {
            errorMessage = "Could not list directory: \(error.localizedDescription)"
            logger.error("Sandbox listing failed: \(error.localizedDescription)")
        }
    }
}

struct AppSandboxExplorerDevToolView: View {
    @State private var viewModel = AppSandboxExplorerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Explore and inspect the active application container directories (Application Support).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Path:")
                        .bold()
                    Text(viewModel.currentDirectory)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("Reload Files") {
                        viewModel.loadSandboxFiles()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else if viewModel.files.isEmpty {
                VStack {
                    Spacer()
                    Text("No sandbox contents resolved or directory is empty.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(viewModel.files, id: \.self) { file in
                    HStack {
                        Image(systemName: file.contains(".") ? "doc" : "folder")
                            .foregroundColor(.blue)
                        Text(file)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("App Sandbox Explorer")
        .onAppear {
            viewModel.loadSandboxFiles()
        }
    }
}
