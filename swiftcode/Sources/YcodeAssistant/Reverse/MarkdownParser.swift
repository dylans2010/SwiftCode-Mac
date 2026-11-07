import Foundation

public struct MarkdownListItem: Sendable, Hashable, Identifiable {
    public var id: String { text + "|" + children.map(\.id).joined(separator: "|") }
    public var text: String
    public var children: [MarkdownListItem]

    public init(text: String, children: [MarkdownListItem] = []) {
        self.text = text
        self.children = children
    }
}

public enum MarkdownBlock: Sendable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case blockQuote(text: String)
    case bulletList(items: [MarkdownListItem])
    case orderedList(items: [MarkdownListItem])
    case horizontalRule

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h-\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .codeBlock(let lang, let code): return "code-\(lang ?? "")-\(code.hashValue)"
        case .blockQuote(let text): return "quote-\(text.hashValue)"
        case .bulletList(let items): return "bullet-\(items.map(\.id).joined().hashValue)"
        case .orderedList(let items): return "ordered-\(items.map(\.id).joined().hashValue)"
        case .horizontalRule: return "rule"
        }
    }
}

@MainActor
public struct MarkdownParser: Sendable {
    public static let shared = MarkdownParser()

    public init() {}

    public func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                let info = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(language: info.isEmpty ? nil : info, code: codeLines.joined(separator: "\n")))
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                var items: [MarkdownListItem] = []
                while i < lines.count {
                    let current = lines[i]
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    guard trimmed.hasPrefix("- ") else { break }
                    let indent = current.prefix(while: { $0 == " " }).count
                    let itemText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)

                    if indent >= 2, let last = items.last {
                        var updatedChildren = last.children
                        updatedChildren.append(MarkdownListItem(text: itemText))
                        items[items.count - 1] = MarkdownListItem(text: last.text, children: updatedChildren)
                    } else {
                        items.append(MarkdownListItem(text: itemText))
                    }
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            if !line.isEmpty {
                blocks.append(.paragraph(text: line))
            }
            i += 1
        }
        return blocks
    }
}
