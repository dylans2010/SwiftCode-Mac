import Foundation

@MainActor
final class AgentSkillManager: ObservableObject {
    static let shared = AgentSkillManager()

    @Published var uploadedSkills: [Skill] = []

    private init() {
        Task {
            uploadedSkills = await SkillsRuntime.shared.getAllSkills()
        }
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
        // Implementation for updating assist capability
        print("[AgentSkillManager] Updating assist capability for \(skillID) to \(enabled)")
    }
}
