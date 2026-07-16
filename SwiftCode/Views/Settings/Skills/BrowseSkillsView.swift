import SwiftUI

struct BrowseSkillsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = AgentSkillManager.shared
    @State private var presetSkills: [AgentSkillBundle] = []
    @State private var selectedSkill: AgentSkillBundle?

    var body: some View {
        NavigationSplitView {
            List(presetSkills, selection: $selectedSkill) { skill in
                NavigationLink(value: skill) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.scheme.name)
                            .font(.headline)
                        Text(skill.scheme.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Preset Library")
            .listStyle(.sidebar)
        } detail: {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.scheme.name)
                                    .font(.title.bold())
                                Text("Author: \(skill.scheme.author) • Version: \(skill.scheme.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                importToActiveSkills(skill)
                            } label: {
                                Label("Install Skill to Agent", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Divider()

                        HStack(spacing: 8) {
                            ForEach(skill.scheme.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }

                        GroupBox("Skill Guidance Rules") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(skill.scheme.guidance, id: \.self) { item in
                                    Label(item, systemImage: "checkmark.seal.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        Text(skill.markdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("Select a Preset Skill", systemImage: "sparkles", description: Text("Browse 20 professional bundled system skill guidelines."))
            }
        }
        .onAppear {
            loadPresets()
        }
    }

    private func loadPresets() {
        var loaded: [AgentSkillBundle] = []
        let parser = SkillsParser()

        // Explicit list of all 20 bundled preset markdown assets
        let files = [
            "avfoundation_processing.SKILLS.md", "combine_streams.SKILLS.md", "core_graphics.SKILLS.md",
            "coredata_thread_safety.SKILLS.md", "custom_layouts.SKILLS.md", "gcd_vs_async_await.SKILLS.md",
            "instruments_profiling.SKILLS.md", "keychain_security.SKILLS.md", "localization_catalogs.SKILLS.md",
            "memory_management.SKILLS.md", "objc_interop.SKILLS.md", "push_notifications.SKILLS.md",
            "sandbox_permissions.SKILLS.md", "spm_integration.SKILLS.md", "swift6_concurrency.SKILLS.md",
            "swiftdata_integration.SKILLS.md", "swiftui_performance.SKILLS.md", "swiftui_state_isolation.SKILLS.md",
            "urlsession_networking.SKILLS.md", "xctest_unit_testing.SKILLS.md"
        ]

        // Load files relative to active bundles or path locations
        let baseDir = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Presets")
        // Check both local bundles or fallback directly on resource paths
        for file in files {
            // Find bundled file
            let url = Bundle.main.url(forResource: file, withExtension: nil) ?? baseDir.appendingPathComponent(file)
            // Try direct path fallback first
            let directPath = "SwiftCode/Views/Settings/Skills/Presets/\(file)"
            do {
                let content: String
                if let contentString = try? String(contentsOfFile: directPath, encoding: .utf8) {
                    content = contentString
                } else if let contentString = try? String(contentsOf: url, encoding: .utf8) {
                    content = contentString
                } else {
                    continue
                }

                let parsed = try parser.parse(content: content, url: url)
                let bundle = AgentSkillBundle(id: parsed.id, scheme: parsed.scheme, markdown: parsed.content, source: .preset)
                loaded.append(bundle)
            } catch {
                print("Failed to parse bundle preset: \(file) - \(error.localizedDescription)")
            }
        }

        presetSkills = loaded
        selectedSkill = loaded.first
    }

    private func importToActiveSkills(_ bundle: AgentSkillBundle) {
        let skill = Skill(
            id: bundle.id,
            name: bundle.scheme.name,
            description: bundle.scheme.summary,
            isEnabled: true,
            content: bundle.markdown,
            scheme: bundle.scheme
        )

        Task {
            do {
                let filename = bundle.scheme.name.lowercased().replacingOccurrences(of: " ", with: "_") + ".SKILLS.md"
                let targetURL = await SkillsRuntime.shared.getBaseSkillsDirectory().appendingPathComponent(filename)
                try await SkillsRuntime.shared.saveSkill(skill, at: targetURL)

                let loaded = await SkillsRuntime.shared.getAllSkills()
                await MainActor.run {
                    manager.uploadedSkills = loaded
                }
            } catch {
                print("Failed to save preset locally: \(error.localizedDescription)")
            }
        }
    }
}
