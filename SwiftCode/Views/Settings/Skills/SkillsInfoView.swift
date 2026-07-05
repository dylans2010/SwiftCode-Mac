import SwiftUI

struct SkillsInfoView: View {
    let skill: AgentSkillBundle
    @StateObject private var manager = AgentSkillManager.shared

    private var formattedMarkdown: AttributedString {
        (try? AttributedString(markdown: skill.markdown)) ?? AttributedString(skill.markdown)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(skill.scheme.name)
                        .font(.title2.weight(.bold))
                    Text(skill.scheme.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                        Text(skill.scheme.author)
                            .font(.caption.weight(.medium))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Skill Version \(skill.scheme.version)")
                            .font(.caption.weight(.medium))
                    }
                    Spacer()
                }

                if !skill.scheme.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(skill.scheme.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                if skill.source == .uploaded {
                    GroupBox {
                        Toggle(
                            "SwiftCode Assist Capable",
                            isOn: Binding(
                                get: { manager.uploadedSkills.first(where: { $0.id == skill.id })?.swiftCodeAssistCapable ?? false },
                                set: { manager.updateAssistCapability(for: skill.id, enabled: $0) }
                            )
                        )
                        .tint(.orange)

                        Text("When enabled, this skill is tagged with \(AssistCapability.toolIdentifier) and always routes through Assist.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Assist API", systemImage: "sparkles")
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(skill.scheme.recommendedTools, id: \.self) { tool in
                            HStack(spacing: 8) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .frame(width: 16)
                                Text(tool)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("Recommended Tools (\(skill.scheme.recommendedTools.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(skill.scheme.guidance.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.orange.opacity(0.7)))
                                Text(item)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text("Guidance")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                GroupBox {
                    Text(formattedMarkdown)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                        Text("Full Documentation")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Skill Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
