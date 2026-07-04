import SwiftUI

public struct SkillsEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var skill: Skill
    @State private var content: String
    @State private var errorMessage: String?
    private let url: URL

    public init(skill: Skill, url: URL) {
        self._skill = State(initialValue: skill)
        self._content = State(initialValue: skill.content)
        self.url = url
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Editing Skill").font(.caption).foregroundStyle(.secondary)
                    Text(skill.name).font(.headline)
                }
                Spacer()
                if let error = errorMessage {
                    Text(error).foregroundColor(.red).font(.caption).padding(.trailing)
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                Button("Close") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding()
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    private func save() {
        Task {
            do {
                let parser = SkillsParser()
                let validator = SkillsValidator()
                let updatedSkill = try parser.parse(content: content, url: url)

                if !validator.validate(skill: updatedSkill) {
                    errorMessage = "Validation failed. Please ensure Skill has a title and valid content."
                    return
                }

                try await SkillsRuntime.shared.saveSkill(updatedSkill, at: url)
                dismiss()
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}
