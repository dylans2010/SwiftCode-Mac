import SwiftUI

public struct FileTemplate: Identifiable, Hashable, Codable {
    public var id: String { originalFileName }
    public let name: String
    public let category: String
    public let description: String
    public let suggestedExtension: String
    public let content: String
    public let originalFileName: String
    public let estimatedLineCount: Int
    public let isFolder: Bool

    public init(
        name: String,
        category: String,
        description: String,
        suggestedExtension: String,
        content: String,
        originalFileName: String,
        estimatedLineCount: Int,
        isFolder: Bool = false
    ) {
        self.name = name
        self.category = category
        self.description = description
        self.suggestedExtension = suggestedExtension
        self.content = content
        self.originalFileName = originalFileName
        self.estimatedLineCount = estimatedLineCount
        self.isFolder = isFolder
    }

    public var iconName: String {
        let lower = category.lowercased()
        if isFolder {
            return "folder.fill"
        }
        if lower.contains("swiftui") {
            return "square.stack.3d.up.fill"
        } else if lower.contains("swift") {
            return "swift"
        } else if lower.contains("appkit") {
            return "macwindow"
        } else if lower.contains("uikit") {
            return "iphone"
        } else if lower.contains("foundation") {
            return "shippingbox.fill"
        } else if lower.contains("testing") {
            return "checkmark.seal.fill"
        } else if lower.contains("apple") || lower.contains("resource") {
            return "list.bullet.rectangle.fill"
        } else if lower.contains("documentation") {
            return "doc.text.fill"
        } else if lower.contains("config") {
            return "gearshape.2.fill"
        } else if lower.contains("web") {
            return "globe"
        } else if lower.contains("ai") {
            return "cpu"
        } else if lower.contains("script") {
            return "terminal.fill"
        } else {
            return "doc.fill"
        }
    }

    public var iconColor: Color {
        if isFolder {
            return .yellow
        }
        let lower = category.lowercased()
        if lower.contains("swiftui") {
            return .cyan
        } else if lower.contains("swift") {
            return .orange
        } else if lower.contains("appkit") {
            return .purple
        } else if lower.contains("uikit") {
            return .indigo
        } else if lower.contains("foundation") {
            return .green
        } else if lower.contains("testing") {
            return .teal
        } else if lower.contains("apple") || lower.contains("resource") {
            return .red
        } else if lower.contains("documentation") {
            return .secondary
        } else if lower.contains("config") {
            return .gray
        } else if lower.contains("web") {
            return .blue
        } else if lower.contains("ai") {
            return .pink
        } else if lower.contains("script") {
            return .primary
        } else {
            return .primary
        }
    }
}
