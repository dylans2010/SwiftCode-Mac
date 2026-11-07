import Foundation

public struct SkillsBundleDiagnostic: Sendable, Equatable, Hashable {
    public enum Severity: String, Sendable, Codable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String
    public let path: String?
    public let lineNumber: Int?

    public init(severity: Severity, message: String, path: String? = nil, lineNumber: Int? = nil) {
        self.severity = severity
        self.message = message
        self.path = path
        self.lineNumber = lineNumber
    }
}

public struct SkillDocument: Sendable, Equatable {
    public let name: String
    public let description: String
    public let body: String

    public init(name: String, description: String, body: String) {
        self.name = name
        self.description = description
        self.body = body
    }

    public func rawMarkdown() -> String {
        """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
    }
}

public enum SkillsBundleTemplate {
    public static let defaultBundleName = "Skills.skillsbundle"
    public static let defaultSkillName = "assistant-actions"

    public static func defaultSkillDocument(name: String = defaultSkillName) -> SkillDocument {
        SkillDocument(
            name: name,
            description: "Guides Siri on resolving task requests and coordinating tool intents for \(name).",
            body: "# \(name.capitalized) Skill\n\nProvide guidance on which intents to choose and parameters to supply."
        )
    }

    public static func createBundle(
        at parentURL: URL,
        bundleName: String = defaultBundleName,
        initialSkillName: String = defaultSkillName
    ) throws -> URL {
        let fileManager = FileManager.default
        let bundleURL = parentURL.appendingPathComponent(bundleName, isDirectory: true)
        let skillsDir = bundleURL.appendingPathComponent("Skills", isDirectory: true)
        let skillFolder = skillsDir.appendingPathComponent(initialSkillName, isDirectory: true)

        try fileManager.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        let skillDoc = defaultSkillDocument(name: initialSkillName)
        let skillFilePath = skillFolder.appendingPathComponent("SKILL.md")
        try skillDoc.rawMarkdown().write(to: skillFilePath, atomically: true, encoding: .utf8)

        return bundleURL
    }
}

public struct SkillsBundleValidator: Sendable {
    public static let maxBodyCharacters = 10000

    public init() {}

    public static func isValidSkillFolderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public func validate(bundleURL: URL) -> [SkillsBundleDiagnostic] {
        var diagnostics: [SkillsBundleDiagnostic] = []
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDir), isDir.boolValue else {
            diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Bundle does not exist or is not a directory", path: bundleURL.path))
            return diagnostics
        }

        guard bundleURL.pathExtension == "skillsbundle" else {
            diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Bundle name must end in .skillsbundle", path: bundleURL.lastPathComponent))
            return diagnostics
        }

        let skillsDir = bundleURL.appendingPathComponent("Skills", isDirectory: true)
        guard fileManager.fileExists(atPath: skillsDir.path, isDirectory: &isDir), isDir.boolValue else {
            diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Skills bundle must contain a top-level 'Skills/' folder", path: bundleURL.path))
            return diagnostics
        }

        if let rootContents = try? fileManager.contentsOfDirectory(atPath: bundleURL.path) {
            for item in rootContents where !item.hasPrefix(".") {
                if item != "Skills" {
                    diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Unexpected file or folder '\(item)' in skills bundle root", path: item))
                }
            }
        }

        guard let skillFolders = try? fileManager.contentsOfDirectory(atPath: skillsDir.path) else {
            return diagnostics
        }

        var observedNames = Set<String>()

        for folderName in skillFolders where !folderName.hasPrefix(".") {
            let skillPath = skillsDir.appendingPathComponent(folderName, isDirectory: true)
            var folderIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: skillPath.path, isDirectory: &folderIsDir), folderIsDir.boolValue else {
                diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "'\(folderName)' inside Skills/ must be a directory", path: folderName))
                continue
            }

            if !Self.isValidSkillFolderName(folderName) {
                diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Skill folder name '\(folderName)' must use only lowercase letters, digits and hyphens", path: folderName))
            }

            guard let files = try? fileManager.contentsOfDirectory(atPath: skillPath.path) else { continue }
            let nonHidden = files.filter { !$0.hasPrefix(".") }

            if !nonHidden.contains("SKILL.md") {
                diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Skill folder '\(folderName)' is missing SKILL.md", path: folderName))
            }

            for extra in nonHidden where extra != "SKILL.md" {
                diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Unexpected file '\(extra)' in skill folder '\(folderName)'. Only SKILL.md is allowed", path: "\(folderName)/\(extra)"))
            }

            let skillFile = skillPath.appendingPathComponent("SKILL.md")
            if let content = try? String(contentsOf: skillFile, encoding: .utf8) {
                let docDiags = validateSkillContent(content, expectedFolderName: folderName, filePath: "\(folderName)/SKILL.md")
                diagnostics.append(contentsOf: docDiags)

                if let doc = parseSkill(content) {
                    if observedNames.contains(doc.name) {
                        diagnostics.append(SkillsBundleDiagnostic(severity: .error, message: "Duplicate skill name '\(doc.name)' across bundle", path: "\(folderName)/SKILL.md"))
                    } else {
                        observedNames.insert(doc.name)
                    }
                }
            }
        }

        return diagnostics
    }

    public func parseSkill(_ content: String) -> SkillDocument? {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        guard let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return nil
        }

        let fmLines = Array(lines[1..<endIndex])
        var name: String?
        var desc: String?

        for line in fmLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                desc = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            }
        }

        guard let n = name, let d = desc else { return nil }
        let body = lines[(endIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return SkillDocument(name: n, description: d, body: body)
    }

    public func validateSkillContent(_ content: String, expectedFolderName: String? = nil, filePath: String = "SKILL.md") -> [SkillsBundleDiagnostic] {
        var diags: [SkillsBundleDiagnostic] = []
        let lines = content.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "SKILL.md must begin with front-matter delimiter '---'", path: filePath, lineNumber: 1))
            return diags
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "Front-matter delimiter '---' was never closed", path: filePath))
            return diags
        }

        let fmLines = Array(lines[1..<endIndex])
        var fields: [String: String] = [:]

        for (idx, line) in fmLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let colon = trimmed.firstIndex(of: ":") else {
                diags.append(SkillsBundleDiagnostic(severity: .error, message: "Invalid YAML line in front-matter: '\(trimmed)'", path: filePath, lineNumber: idx + 2))
                continue
            }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = val
        }

        for key in fields.keys where key != "name" && key != "description" {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "Unknown front-matter field '\(key)'. Only 'name' and 'description' are allowed", path: filePath))
        }

        guard let name = fields["name"], !name.isEmpty else {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "Missing required front-matter field 'name'", path: filePath))
            return diags
        }

        guard let desc = fields["description"], !desc.isEmpty else {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "Missing required front-matter field 'description'", path: filePath))
            return diags
        }

        let body = lines[(endIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count > Self.maxBodyCharacters {
            diags.append(SkillsBundleDiagnostic(severity: .error, message: "Skill body length (\(body.count)) exceeds maximum allowed of \(Self.maxBodyCharacters) characters", path: filePath))
        }

        return diags
    }
}
