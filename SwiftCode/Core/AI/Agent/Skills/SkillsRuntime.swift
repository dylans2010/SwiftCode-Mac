import Foundation

public actor SkillsRuntime {
    public static let shared = SkillsRuntime()

    private var skills: [Skill] = []
    private let parser = SkillsParser()
    private let validator = SkillsValidator()

    private init() {}

    public func discoverSkills(in directory: URL) async throws -> [Skill] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var discoveredSkills: [Skill] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.hasSuffix(".SKILLS.md") || fileURL.lastPathComponent == "SKILLS.md" {
                do {
                    let content = try String(contentsOf: fileURL, encoding: .utf8)
                    var skill = try parser.parse(content: content, url: fileURL)

                    // Restore enabled state from UserDefaults
                    let isEnabled = UserDefaults.standard.bool(forKey: "skill_enabled_\(skill.id.uuidString)")
                    skill.isEnabled = isEnabled || !UserDefaults.standard.dictionaryRepresentation().keys.contains("skill_enabled_\(skill.id.uuidString)")

                    if validator.validate(skill: skill) {
                        discoveredSkills.append(skill)
                    }
                } catch {
                    LoggingTool.error("Failed to parse skill at \(fileURL.path): \(error)")
                }
            }
        }

        self.skills = discoveredSkills
        return discoveredSkills
    }

    public func getActiveSkillsContent() async -> String {
        return skills.filter { $0.isEnabled }
            .map { $0.content }
            .joined(separator: "\n\n---\n\n")
    }

    public func getAllSkills() async -> [Skill] {
        return skills
    }

    public func toggleSkill(id: UUID) async {
        if let index = skills.firstIndex(where: { $0.id == id }) {
            skills[index].isEnabled.toggle()
            UserDefaults.standard.set(skills[index].isEnabled, forKey: "skill_enabled_\(id.uuidString)")
        }
    }

    public func saveSkill(_ skill: Skill, at url: URL) async throws {
        try skill.content.write(to: url, options: .atomic, encoding: .utf8)
        // Refresh local state
        let updatedSkill = try parser.parse(content: skill.content, url: url)
        if let index = skills.firstIndex(where: { $0.id == updatedSkill.id }) {
            skills[index] = updatedSkill
        } else {
            skills.append(updatedSkill)
        }
    }

    public func deleteSkill(id: UUID) async throws {
        if let index = skills.firstIndex(where: { $0.id == id }), let url = skills[index].url {
            try FileManager.default.removeItem(at: url)
            skills.remove(at: index)
        }
    }

    public func getBaseSkillsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("SwiftCode", isDirectory: true)
        let skillsDir = appSupport.appendingPathComponent("Skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        return skillsDir
    }
}
