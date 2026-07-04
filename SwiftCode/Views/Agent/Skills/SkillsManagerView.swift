import SwiftUI

public struct SkillsManagerView: View {
    @State private var skills: [Skill] = []
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var showingCreate = false

    public init() {}

    public var body: some View {
        VStack {
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

            List {
                ForEach(filteredSkills) { skill in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(skill.name).font(.headline)
                            Text(skill.description).font(.subheadline).foregroundColor(.secondary)
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
                    .contextMenu {
                        Button("Duplicate") { /* Logic */ }
                        Button("Edit") { /* Logic */ }
                        Button("Delete", role: .destructive) { /* Logic */ }
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
        .navigationTitle("Skills Manager")
    }

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return skills }
        return skills.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    private func refresh() async {
        skills = await SkillsRuntime.shared.getAllSkills()
    }
}

public struct SkillsImportView: View {
    @Environment(\.dismiss) var dismiss
    public var body: some View {
        VStack {
            Text("Import SKILLS.md").font(.headline)
            Button("Select File") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.markdown]
                if panel.runModal() == .OK {
                    // Import logic
                    dismiss()
                }
            }
            Button("Cancel") { dismiss() }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

public struct SkillsCreateView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var content = ""

    public var body: some View {
        VStack {
            Text("Create New Skill").font(.headline)
            TextField("Name", text: $name)
            TextEditor(text: $content)
                .border(Color.secondary)
            HStack {
                Button("Save") { dismiss() }
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}
