import SwiftUI
import UniformTypeIdentifiers

struct ImportProjView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Import .scproj File")
                    .font(.title2)
                    .bold()
                Text("Select a SwiftCode project file to import it into your library. The file's signature will be verified before import.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isImporting {
                ProgressView("Importing project...")
            } else {
                Button(action: selectAndImportFile) {
                    Label("Select .scproj File...", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let error = errorMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 450, height: 400)
    }

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "scproj")].compactMap { $0 }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            importFile(at: url)
        }
    }

    private func importFile(at url: URL) {
        isImporting = true
        errorMessage = nil

        Task {
            do {
                let project = try await SCProjManager.shared.importProject(from: url)
                await projectManager.openProject(project)
                dismiss()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Import failed: \(error.localizedDescription)"
                    self.isImporting = false
                }
            }
        }
    }
}
