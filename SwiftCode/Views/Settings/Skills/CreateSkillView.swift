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
            ScrollView {
                VStack(spacing: 24) {
                    // GroupBox 1: Skill Metadata
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Skill Metadata", systemImage: "info.circle")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Skill Name")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. CoreData Pro", text: $name)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Summary Description")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("Provide a brief summary of the skill guidelines", text: $summary)
                                        .textFieldStyle(.roundedBorder)
                                }

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Version")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        TextField("1.0.0", text: $version)
                                            .textFieldStyle(.roundedBorder)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Author")
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)
                                        TextField("Author Name", text: $author)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tags")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("Comma separated (e.g. swift, ios, ui)", text: $tagsString)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox 2: Guidelines & Markdown Content
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Guidelines & Instructions (Markdown)", systemImage: "doc.text")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            TextEditor(text: $markdownContent)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 220)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox 3: Actions
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Actions", systemImage: "play.circle")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            VStack(spacing: 10) {
                                Button {
                                    Task { await saveSkill() }
                                } label: {
                                    HStack {
                                        if isSaving {
                                            ProgressView().scaleEffect(0.8).padding(.trailing, 8)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                        }
                                        Text(isSaving ? "Saving Skill..." : "Save Skill to Active Skills")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(name.isEmpty || markdownContent.isEmpty || isSaving)

                                Button("Cancel") {
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                                .disabled(isSaving)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if let errorMessage {
                        GroupBox {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("Manual Skill Editor")
        }
        .frame(width: 550, height: 650)
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
