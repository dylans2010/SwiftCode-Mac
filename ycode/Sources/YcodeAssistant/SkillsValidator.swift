// Adapted from SwiftCode-Legacy SwiftCode/Core/AI/Agent/Skills/SkillsValidator.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct SkillsValidator: Sendable {
    public init() {}

    public func validate(skill: Skill) -> Bool {
        // Basic validation
        if skill.name.isEmpty || skill.name == "Unknown Skill" {
            return false
        }

        if skill.content.isEmpty {
            return false
        }

        // Skill must have at least one heading and some content
        if !skill.content.contains("# ") {
            return false
        }

        // Check for disallowed placeholders
        let prohibited = ["TODO", "FIXME", "<PLACEHOLDER>", "INSERT CONTENT HERE"]
        for word in prohibited {
            if skill.content.localizedCaseInsensitiveContains(word) {
                return false
            }
        }

        return true
    }
}
