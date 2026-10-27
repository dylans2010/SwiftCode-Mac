import SwiftUI
import UniformTypeIdentifiers

struct ImportProjView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var importManager = ImportProjManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.106, green: 0.404, blue: 0.863).opacity(0.18))
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 0.98))
            }
            .frame(width: 72, height: 72)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.106, green: 0.404, blue: 0.863).opacity(0.3), lineWidth: 1)
            )

            VStack(spacing: 8) {
                Text("Import SwiftCode Project Archive")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Select a .scproj archive to verify integrity and restore into your workspaces.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            if importManager.isImporting {
                VStack(spacing: 12) {
                    ProgressView(value: importManager.importProgress)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0.106, green: 0.404, blue: 0.863))
                    Text("Importing project... \(Int(importManager.importProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 24)
            } else {
                Button(action: selectAndImportFile) {
                    Label("Select Archive File...", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(red: 0.106, green: 0.404, blue: 0.863))
            }

            if let error = importManager.importError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(importManager.isImporting)
        }
        .padding(32)
        .frame(width: 480, height: 400)
        .background(Color(red: 0.082, green: 0.102, blue: 0.180))
        .preferredColorScheme(.dark)
    }

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        if let scprojType = UTType(filenameExtension: "scproj") {
            panel.allowedContentTypes = [scprojType]
        } else {
            panel.allowedContentTypes = [UTType(exportedAs: "com.swiftcode.project")]
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await importManager.importProject(from: url)
                    try? sessionStore.saveMetadataInPlace(project)

                    var currentProjects = sessionStore.projects
                    if !currentProjects.contains(where: { $0.id == project.id }) {
                        currentProjects.insert(project, at: 0)
                    }
                    sessionStore.projects = currentProjects
                    sessionStore.loadProjects()

                    await sessionStore.openProject(project)
                    dismiss()
                } catch {
                    // Error is handled by importManager
                }
            }
        }
    }
}
