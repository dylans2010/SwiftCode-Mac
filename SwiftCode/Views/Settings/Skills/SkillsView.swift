import SwiftUI

struct SkillsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AgentSkillManager.shared
    @State private var showAddView = false
    @State private var searchText = ""
    @State private var selectedTag: String?

    private var allTags: [String] {
        let tags = manager.allSkills.flatMap { $0.scheme.tags }
        return Array(Set(tags)).sorted()
    }

    private var filteredPresets: [AgentSkillBundle] {
        filterSkills(manager.presetSkills)
    }

    private var filteredUploaded: [AgentSkillBundle] {
        let uploaded = manager.uploadedSkills.map {
            AgentSkillBundle(id: $0.id, scheme: $0.scheme, markdown: $0.content, source: .uploaded)
        }
        return filterSkills(uploaded)
    }

    private func filterSkills(_ skills: [AgentSkillBundle]) -> [AgentSkillBundle] {
        skills.filter { skill in
            let matchesSearch = searchText.isEmpty ||
                skill.scheme.name.localizedCaseInsensitiveContains(searchText) ||
                skill.scheme.summary.localizedCaseInsensitiveContains(searchText)
            let matchesTag = selectedTag == nil || skill.scheme.tags.contains(selectedTag!)
            return matchesSearch && matchesTag
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("PRESET SKILLS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)) {
                    if filteredPresets.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("No matching preset skills found.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(filteredPresets) { skill in
                            NavigationLink {
                                SkillsInfoView(skill: skill)
                            } label: {
                                skillRow(skill)
                            }
                        }
                    }
                }

                Section(header: Text("UPLOADED SKILLS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)) {
                    if filteredUploaded.isEmpty {
                        // FIX: Explicitly render an empty state row inside the section to guarantee it shows
                        HStack(spacing: 8) {
                            Image(systemName: "brain.slash")
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Uploaded Skills")
                                    .fontWeight(.medium)
                                Text("Upload or draft custom coding skills using the add panel.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(filteredUploaded) { skill in
                            NavigationLink {
                                SkillsInfoView(skill: skill)
                            } label: {
                                skillRow(skill)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Agent Skills")
            .searchable(text: $searchText, prompt: "Search agent skills...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddView = true
                    } label: {
                        Label("Add Skill Pack", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddView) {
            SkillsAddView()
        }
    }

    private func skillRow(_ skill: AgentSkillBundle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.scheme.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("v\(skill.scheme.version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(skill.scheme.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text("\(skill.scheme.recommendedTools.count) Tools")
                    .font(.caption2)
                    .foregroundStyle(.orange)

                ForEach(skill.scheme.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
