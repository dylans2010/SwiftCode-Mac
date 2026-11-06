//
//  SkillDescriptor.swift
//  SwiftCode
//
//  Unified, strongly-typed descriptor for agent skills across all discovery ecosystems.
//

import Foundation

public enum SkillSourceKind: String, Codable, Sendable, CaseIterable {
    case swiftcode = "SwiftCode"
    case codex = "Codex"
    case claude = "Claude"
    case vscode = "VS Code"
    case antigravity = "Antigravity"
    case project = "Project"
    case user = "User"
    case other = "External"

    public var iconName: String {
        switch self {
        case .swiftcode: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "brain.head.profile"
        case .vscode: return "curlybraces"
        case .antigravity: return "atom"
        case .project: return "folder.fill"
        case .user: return "person.crop.circle"
        case .other: return "puzzlepiece.extension"
        }
    }
}

public struct SkillDescriptor: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let path: String
    public let sourceKind: SkillSourceKind
    public let sourceDescription: String
    public let originalPath: String?
    public let tags: [String]
    public let recommendedTools: [String]
    public let searchableText: String
    public let lastModified: Date
    public var isEnabled: Bool

    public init(
        id: String,
        name: String,
        description: String,
        path: String,
        sourceKind: SkillSourceKind = .swiftcode,
        sourceDescription: String = "Authoritative SwiftCode Local Store",
        originalPath: String? = nil,
        tags: [String] = [],
        recommendedTools: [String] = [],
        searchableText: String = "",
        lastModified: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.path = path
        self.sourceKind = sourceKind
        self.sourceDescription = sourceDescription
        self.originalPath = originalPath
        self.tags = tags
        self.recommendedTools = recommendedTools
        self.searchableText = searchableText.isEmpty ? "\(name) \(description) \(tags.joined(separator: " "))" : searchableText
        self.lastModified = lastModified
        self.isEnabled = isEnabled
    }

    /// Loads the actual SKILL.md instruction contents from disk.
    public var skillMarkdownContent: String? {
        let skillUrl = URL(fileURLWithPath: path).appendingPathComponent("SKILL.md")
        return try? String(contentsOf: skillUrl, encoding: .utf8)
    }
}
