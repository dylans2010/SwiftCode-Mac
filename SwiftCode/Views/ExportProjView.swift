import SwiftUI
import UniformTypeIdentifiers

struct ExportProjView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var exportManager = ExportProjManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if let project = projectManager.activeProject {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Export \"\(project.name)\"")
                    .font(.title2)
                    .bold()

                Text("This will create a .scproj package containing all project data, files, and metadata. The package includes integrity verification.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if exportManager.isExporting {
                    VStack(spacing: 12) {
                        ProgressView(value: exportManager.exportProgress)
                            .progressViewStyle(.linear)
                        Text("Exporting... \(Int(exportManager.exportProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: selectDestinationAndExport) {
                        Label("Export Project", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                Text("No active project to export.")
            }

            if let error = exportManager.exportError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func selectDestinationAndExport() {
        guard let project = projectManager.activeProject else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.swiftcode.project")]
        panel.nameFieldStringValue = "\(project.name).scproj"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await exportManager.exportProject(project, to: url)
                    dismiss()
                } catch {
                    // Error is handled by ExportProjManager
                }
            }
        }
    }
}
