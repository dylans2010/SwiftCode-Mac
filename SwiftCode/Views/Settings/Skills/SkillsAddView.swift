import SwiftUI
import UniformTypeIdentifiers

struct SkillsAddView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AgentSkillManager.shared

    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Upload a .zip containing skills.md and scheme.json")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button {
                    showImporter = true
                } label: {
                    Label("Import Skill Zip", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                if let importError {
                    Text(importError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                List(manager.uploadedSkills) { skill in
                    VStack(alignment: .leading) {
                        Text(skill.scheme.name)
                            .font(.subheadline.weight(.semibold))
                        Text(skill.scheme.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .navigationTitle("Add Skills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showImporter) {
            FileImporterRepresentableView(
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { urls in
                showImporter = false
                guard let url = urls.first else { return }
                do {
                    try manager.importSkillArchive(at: url)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }
}
