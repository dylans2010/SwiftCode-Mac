import SwiftUI
import UniformTypeIdentifiers

struct ImportProjView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var importManager = ImportProjManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.down.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Import .scproj Project")
                    .font(.title2)
                    .bold()
                Text("Select a SwiftCode project package to import it into your library. The project's integrity will be verified.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if importManager.isImporting {
                VStack(spacing: 12) {
                    ProgressView(value: importManager.importProgress)
                        .progressViewStyle(.linear)
                    Text("Importing project... \(Int(importManager.importProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: selectAndImportFile) {
                    Label("Select .scproj Project...", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
            .disabled(importManager.isImporting)
        }
        .padding(32)
        .frame(width: 450, height: 400)
    }

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.swiftcode.project")]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false // It's a package, treated as a file in picker if UTI is correct

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let project = try await importManager.importProject(from: url)
                    await projectManager.saveImportedProject(project)
                    await projectManager.openProject(project)
                    dismiss()
                } catch {
                    // Error is handled by ImportProjManager @Published property
                }
            }
        }
    }
}
