import Foundation

public struct SkillsValidator: Sendable {
    public init() {}

    public func validate(skill: Skill) -> Bool {
        if skill.name.isEmpty || skill.name == "Unknown Skill" {
            return false
        }

        if skill.content.isEmpty {
            return false
        }

        if !skill.content.contains("# ") {
            return false
        }

        let prohibited = ["TODO", "FIXME", "<PLACEHOLDER>", "INSERT CONTENT HERE"]
        for word in prohibited {
            if skill.content.localizedCaseInsensitiveContains(word) {
                return false
            }
        }

        return true
    }
}
