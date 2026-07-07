import Foundation

@MainActor
final class AgentSkillManager: ObservableObject {
    static let shared = AgentSkillManager()

    @Published var uploadedSkills: [Skill] = [] {
        didSet { updateAllSkills() }
    }

    @Published var presetSkills: [AgentSkillBundle] = [] {
        didSet { updateAllSkills() }
    }

    @Published var allSkills: [AgentSkillBundle] = []

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

    func resetUploadedSkills() {
        Task {
            let skills = await SkillsRuntime.shared.getAllSkills()
            for skill in skills {
                try? await SkillsRuntime.shared.deleteSkill(id: skill.id)
            }
            uploadedSkills = []
        }
    }

    func updateAssistCapability(for skillID: UUID, enabled: Bool) {
        if let index = uploadedSkills.firstIndex(where: { $0.id == skillID }) {
            uploadedSkills[index].swiftCodeAssistCapable = enabled
            print("[AgentSkillManager] Updating assist capability for \(skillID) to \(enabled)")
        }
    }

    func importSkillArchive(at url: URL) throws {
        print("[AgentSkillManager] Importing skill archive from \(url.path)")
        // Actual implementation would involve ZipImporter and SkillsRuntime
    }
}
