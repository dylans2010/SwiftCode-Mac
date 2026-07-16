import SwiftUI

struct CreateSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AgentSkillManager.shared

    @State private var name = ""
    @State private var summary = ""
    @State private var version = "1.0.0"
    @State private var author = ""
    @State private var tagsString = "swift, ios, ui"
    @State private var markdownContent = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill Metadata") {
                    TextField("Skill Name (e.g. CoreData Pro)", text: $name)
                    TextField("Summary Description", text: $summary)
                    HStack {
                        TextField("Version", text: $version)
                        TextField("Author", text: $author)
                    }
                    TextField("Tags (comma separated)", text: $tagsString)
                }

                Section("Skill Guidelines & Instructions (Markdown)") {
                    TextEditor(text: $markdownContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Manual Skill Editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save Skill") {
                            Task { await saveSkill() }
                        }
                        .disabled(name.isEmpty || markdownContent.isEmpty)
                    }
                }
            }
        }
        .frame(width: 550, height: 500)
    }

    private func saveSkill() async {
        isSaving = true
        errorMessage = nil

        let tags = tagsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let scheme = SkillScheme(
            name: name,
            summary: summary,
            version: version,
            author: author,
            tags: tags,
            recommendedTools: ["edit_file", "read_file"],
            guidance: ["Write clean compile-safe Swift code."]
        )

        let skill = Skill(
            id: UUID(),
            name: name,
            description: summary,
            content: markdownContent,
            scheme: scheme
        )

        do {
            let filename = name.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines) + ".SKILLS.md"

            let skillsDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
            let fileURL = skillsDir.appendingPathComponent(filename)

            try await SkillsRuntime.shared.saveSkill(skill, at: fileURL)

            // Reload skills in manager
            let loaded = await SkillsRuntime.shared.getAllSkills()
            await MainActor.run {
                manager.uploadedSkills = loaded
                dismiss()
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
