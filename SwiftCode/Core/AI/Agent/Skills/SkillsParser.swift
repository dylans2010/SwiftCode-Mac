import Foundation

public struct SkillsParser: Sendable {
    public init() {}

    public func parse(content: String) throws -> Skill {
        // Simple parser that looks for a name in the first H1
        let lines = content.components(separatedBy: .newlines)
        let name = lines.first(where: { $0.hasPrefix("# ") })?.dropFirst(2).trimmingCharacters(in: .whitespaces) ?? "Unknown Skill"
        let description = lines.first(where: { !$0.hasPrefix("#") && !$0.isEmpty }) ?? "No description"

        return Skill(name: String(name), description: String(description), content: content)
    }
}
