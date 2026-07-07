import SwiftUI

struct ExportProjView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        VStack(spacing: 20) {
            if let project = projectManager.activeProject {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)

                Text("Export \"\(project.name)\"")
                    .font(.title2)
                    .bold()

                Text("This will create a .scproj file containing all project data and files. The file will be signed to ensure integrity.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                InfoProjView(project: project)
                    .frame(height: 300)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))

                if isExporting {
                    ProgressView("Exporting...")
                } else {
                    Button(action: exportProject) {
                        Label("Export Project", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                Text("No active project to export.")
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .background(exportURL != nil ? Color.clear : Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportProject() {
        guard let project = projectManager.activeProject else { return }
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let url = try await SCProjManager.shared.exportProject(project)
                await MainActor.run {
                    self.exportURL = url
                    self.isExporting = false
                    self.showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Export failed: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
}
