import Foundation

public struct SkillsRuntime {
    public static let shared = SkillsRuntime()

    public init() {}

    public func discoverSkills(in directory: URL) async throws -> [Skill] {
        // Implementation of discovery
        return []
    }

    public func getActiveSkillsContent() async -> String {
        return ""
    }

    public func getAllSkills() async -> [Skill] {
        return []
    }

    public func toggleSkill(id: UUID) async {}
}
