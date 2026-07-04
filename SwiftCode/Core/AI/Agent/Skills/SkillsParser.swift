import Foundation

public struct SkillsParser: Sendable {
    public init() {}

    public func parse(content: String, url: URL? = nil) throws -> Skill {
        let lines = content.components(separatedBy: .newlines)

        // Extract Name from first H1
        let name = lines.first(where: { $0.hasPrefix("# ") })?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces) ?? "Unknown Skill"

        // Extract Description from first non-empty line after title
        var description = "No description"
        if let titleIndex = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            for i in (titleIndex + 1)..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if !line.isEmpty && !line.hasPrefix("#") {
                    description = line
                    break
                }
            }
        }

        // Extract Metadata (YAML-like block at top if exists)
        var metadata: [String: String] = [:]
        if content.hasPrefix("---") {
            let parts = content.components(separatedBy: "---")
            if parts.count >= 3 {
                let yamlLines = parts[1].components(separatedBy: .newlines)
                for line in yamlLines {
                    let kv = line.components(separatedBy: ":")
                    if kv.count == 2 {
                        let key = kv[0].trimmingCharacters(in: .whitespaces)
                        let value = kv[1].trimmingCharacters(in: .whitespaces)
                        metadata[key] = value
                    }
                }
            }
        }

        // Use a consistent UUID if provided in metadata, otherwise generate new
        let id = metadata["id"].flatMap { UUID(uuidString: $0) } ?? UUID()

        return Skill(
            id: id,
            name: String(name),
            description: String(description),
            isEnabled: true,
            content: content,
            metadata: metadata,
            url: url
        )
    }
}
