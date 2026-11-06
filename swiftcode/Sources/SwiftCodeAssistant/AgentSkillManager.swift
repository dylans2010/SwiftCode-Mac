// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/AgentSkillManager.swift
//
// Adapted for SwiftCode: access raised to public (the type is used
// from swiftcode-ide views — BrowseSkillsView, CreateSkillView,
// SkillsAddView, SkillsInfoView, SkillsView — which live in another
// module). Behaviour unchanged. `Skill`, `AgentSkillBundle` and
// `SkillsRuntime` already live in this target.

import Foundation

@MainActor
public final class AgentSkillManager: ObservableObject {
    public static let shared = AgentSkillManager()

    @Published public var uploadedSkills: [Skill] = [] {
        didSet { updateAllSkills() }
    }

    @Published public var presetSkills: [AgentSkillBundle] = [] {
        didSet { updateAllSkills() }
    }

    @Published public var allSkills: [AgentSkillBundle] = []

    private init() {
        Task {
            uploadedSkills = await SkillsRuntime.shared.getAllSkills()
            updateAllSkills()
        }
    }

    private func updateAllSkills() {
        let uploaded = uploadedSkills.map {
            AgentSkillBundle(id: $0.id, scheme: $0.scheme, markdown: $0.content, source: .uploaded)
        }
        allSkills = presetSkills + uploaded
    }

    public func resetUploadedSkills() {
        Task {
            let skills = await SkillsRuntime.shared.getAllSkills()
            for skill in skills {
                try? await SkillsRuntime.shared.deleteSkill(id: skill.id)
            }
            uploadedSkills = []
        }
    }

    public func updateAssistCapability(for skillID: UUID, enabled: Bool) {
        if let index = uploadedSkills.firstIndex(where: { $0.id == skillID }) {
            uploadedSkills[index].swiftCodeAssistCapable = enabled
            print("[AgentSkillManager] Updating assist capability for \(skillID) to \(enabled)")
        }
    }

    public func importSkillArchive(at url: URL) throws {
        print("[AgentSkillManager] Importing skill archive from \(url.path)")
        // Actual implementation would involve ZipImporter and SkillsRuntime
    }
}
