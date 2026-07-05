import Foundation
import SwiftUI

// Represents a file or folder in the project navigator
public class FileNode: Identifiable, ObservableObject, Codable {
    public var id: UUID
    public var name: String
    public var path: String // relative path from project root
    public var isDirectory: Bool
    @Published public var children: [FileNode]
    @Published public var isExpanded: Bool

    public enum CodingKeys: String, CodingKey {
        case id, name, path, isDirectory, children
    }

    public init(name: String, path: String, isDirectory: Bool, children: [FileNode] = []) {
        self.id = UUID()
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = false
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        children = try container.decode([FileNode].self, forKey: .children)
        isExpanded = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(children, forKey: .children)
    }

    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    public var icon: String {
        if isDirectory { return "folder.fill" }
        switch fileExtension {
        case "swift": return "swift"
        case "json": return "curlybraces"
        case "plist": return "list.bullet"
        case "md": return "doc.text"
        case "txt": return "doc.plaintext"
        case "yml", "yaml": return "gearshape"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "xcodeproj": return "hammer"
        default: return "doc"
        }
    }

    public var iconColor: Color {
        if isDirectory { return .blue }
        switch fileExtension {
        case "swift": return .orange
        case "json": return .yellow
        case "plist": return .purple
        case "md": return .green
        case "yml", "yaml": return .teal
        case "png", "jpg", "jpeg", "gif", "svg": return .pink
        default: return .gray
        }
    }
}

extension FileNode: Equatable {
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        return lhs.id == rhs.id
    }
}
