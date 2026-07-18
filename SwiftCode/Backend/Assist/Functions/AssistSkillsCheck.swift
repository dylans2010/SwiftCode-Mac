import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "assist.skillsDiscovery")

public struct SkillContext: Codable, Sendable, Hashable {
    public let name: String
    public let description: String
    public let author: String
    public let version: String
    public let tags: [String]
    public let recommendedTools: [String]
    public let guidance: [String]
}

public final class AssistSkillsCheck: Sendable {
    public static let shared = AssistSkillsCheck()

    private init() {}

    public func discoverSkills() async -> [SkillContext] {
        var discovered: [SkillContext] = []
        let fileManager = FileManager.default

        let possiblePaths = [
            Bundle.main.resourceURL?.appendingPathComponent("Skills"),
            Bundle.main.resourceURL?.appendingPathComponent("Presets"),
            URL(fileURLWithPath: "SwiftCode/Views/Settings/Skills/Presets"),
            URL(fileURLWithPath: "SwiftCode/Views/Settings/Skills")
        ]

        logger.log("[discoverSkills] Scanning for dynamic skills in local and resource directories.")
        DiagnosticEventBus.shared.logEvent(
            component: "AssistSkillsCheck",
            severity: "INFO",
            category: "system",
            message: "Scanning for dynamic skills in local and resource directories"
        )

        for pathURL in possiblePaths {
            guard let url = pathURL else { continue }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                do {
                    let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    for fileURL in contents {
                        if fileURL.lastPathComponent.hasSuffix(".SKILLS.md") || fileURL.lastPathComponent == "SKILLS.md" {
                            do {
                                let content = try String(contentsOf: fileURL, encoding: .utf8)
                                if let parsed = parseSkillMetadata(from: content) {
                                    discovered.append(parsed)
                                    logger.log("[discoverSkills] Successfully parsed skill: \(parsed.name)")
                                }
                            } catch {
                                logger.error("[discoverSkills] Failed to read skill file at \(fileURL.path): \(error.localizedDescription)")
                                DiagnosticEventBus.shared.logEvent(
                                    component: "AssistSkillsCheck",
                                    severity: "WARN",
                                    errorDescription: error.localizedDescription,
                                    category: "system",
                                    message: "Failed to read skill file at \(fileURL.path)"
                                )
                            }
                        }
                    }
                } catch {
                    logger.error("[discoverSkills] Failed to list contents of directory \(url.path): \(error.localizedDescription)")
                    DiagnosticEventBus.shared.logEvent(
                        component: "AssistSkillsCheck",
                        severity: "WARN",
                        errorDescription: error.localizedDescription,
                        category: "system",
                        message: "Failed to list contents of directory \(url.path)"
                    )
                }
            }
        }

        logger.log("[discoverSkills] Discovered \(discovered.count) skills.")
        DiagnosticEventBus.shared.logEvent(
            component: "AssistSkillsCheck",
            severity: "INFO",
            category: "system",
            message: "Discovered \(discovered.count) skills"
        )
        return discovered
    }

    private func parseSkillMetadata(from content: String) -> SkillContext? {
        let lines = content.components(separatedBy: .newlines)

        // Extract Name from first H1
        let name = lines.first(where: { $0.hasPrefix("# ") })?
            .dropFirst(2)
            .trimmingCharacters(in: .whitespaces) ?? "Unknown Skill"

        // Extract Description/Summary from first non-empty line after title
        var summary = "No description"
        if let titleIndex = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            for i in (titleIndex + 1)..<lines.count {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if !line.isEmpty && !line.hasPrefix("#") {
                    summary = line
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

        let author = metadata["author"] ?? "SwiftCode"
        let version = metadata["version"] ?? "1.0.0"
        let tags = metadata["tags"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let recommendedTools = metadata["recommendedTools"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let guidance = metadata["guidance"]?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

        return SkillContext(
            name: name,
            description: summary,
            author: author,
            version: version,
            tags: tags,
            recommendedTools: recommendedTools,
            guidance: guidance
        )
    }
}
