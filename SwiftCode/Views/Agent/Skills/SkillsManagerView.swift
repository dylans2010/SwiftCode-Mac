import SwiftUI

public struct SkillsManagerView: View {
    @State private var skills: [Skill] = []
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var showingCreate = false
    @State private var selectedSkill: Skill?
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                HStack {
                    Text(error)
                    Spacer()
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
            }

            HStack {
                TextField("Search Skills...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button(action: { showingImport = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button(action: { showingCreate = true }) {
                    Label("Create", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            List {
                ForEach(filteredSkills) { skill in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(skill.name).font(.headline)
                            Text(skill.description).font(.subheadline).foregroundColor(.secondary)
                            if let url = skill.url {
                                Text(url.lastPathComponent).font(.caption2).foregroundColor(.tertiary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { skill.isEnabled },
                            set: { _ in
                                Task {
                                    await SkillsRuntime.shared.toggleSkill(id: skill.id)
                                    await refresh()
                                }
                            }
                        ))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSkill = skill
                    }
                    .contextMenu {
                        Button("Edit") {
                            selectedSkill = skill
                        }
                        Button("Duplicate") {
                            duplicate(skill)
                        }
                        Button("Delete", role: .destructive) {
                            delete(skill)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await refresh() }
        }
        .sheet(isPresented: $showingImport) {
            SkillsImportView()
        }
        .sheet(isPresented: $showingCreate) {
            SkillsCreateView()
        }
        .sheet(item: $selectedSkill) { skill in
            if let url = skill.url {
                SkillsEditorView(skill: skill, url: url)
            } else {
                Text("Error: Skill source URL not found.").padding()
            }
        }
        .navigationTitle("Skills Manager")
    }

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return skills }
        return skills.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    private func refresh() async {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        _ = try? await SkillsRuntime.shared.discoverSkills(in: projectRoot)
        skills = await SkillsRuntime.shared.getAllSkills()
    }

    private func duplicate(_ skill: Skill) {
        Task {
            do {
                let newContent = skill.content.replacingOccurrences(of: "# \(skill.name)", with: "# \(skill.name) Copy")
                let parser = SkillsParser()
                let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
                let newUrl = baseDir.appendingPathComponent("\(skill.name) Copy.SKILLS.md")
                let newSkill = try parser.parse(content: newContent, url: newUrl)
                try await SkillsRuntime.shared.saveSkill(newSkill, at: newUrl)
                await refresh()
            } catch {
                errorMessage = "Failed to duplicate: \(error.localizedDescription)"
            }
        }
    }

    private func delete(_ skill: Skill) {
        Task {
            do {
                try await SkillsRuntime.shared.deleteSkill(id: skill.id)
                await refresh()
            } catch {
                errorMessage = "Failed to delete: \(error.localizedDescription)"
            }
        }
    }
}

public struct SkillsImportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var errorMessage: String?

    public var body: some View {
        VStack {
            Text("Import SKILLS.md").font(.headline)
            Text("Select a markdown file to import as a skill.").font(.subheadline).foregroundStyle(.secondary)

            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption).padding()
            }

            Spacer()

            HStack {
                Button("Select File") {
                    importFile()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown]
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    let content = try String(contentsOf: url)
                    let skill = try SkillsParser().parse(content: content)
                    let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
                    let destUrl = baseDir.appendingPathComponent(url.lastPathComponent)
                    try await SkillsRuntime.shared.saveSkill(skill, at: destUrl)
                    dismiss()
                } catch {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

public struct SkillsCreateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var content = "# New Skill\n\nDescription here."
    @State private var errorMessage: String?

    public var body: some View {
        VStack {
            Text("Create New Skill").font(.headline)
            TextField("Name (used for filename)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.2))

            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption).padding(.top)
            }

            HStack {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }

    private func save() {
        Task {
            do {
                let skill = try SkillsParser().parse(content: content)
                let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
                let url = baseDir.appendingPathComponent("\(name).SKILLS.md")
                try await SkillsRuntime.shared.saveSkill(skill, at: url)
                dismiss()
            } catch {
                errorMessage = "Failed to create skill: \(error.localizedDescription)"
            }
        }
    }
}
