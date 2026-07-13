import Foundation
import SwiftUI
import Markdown

public enum MarkdownBlock: Sendable, Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case blockQuote(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case taskList(items: [(checked: Bool, text: String)])
    case horizontalRule
    case table(headers: [String], rows: [[String]])

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h-\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .codeBlock(let lang, let code): return "code-\(lang ?? "")-\(code.hashValue)"
        case .blockQuote(let text): return "quote-\(text)"
        case .bulletList(let items): return "bullet-\(items.joined().hashValue)"
        case .orderedList(let items): return "ordered-\(items.joined().hashValue)"
        case .taskList(let items): return "task-\(items.map { "\($0.checked)-\($0.text)" }.joined().hashValue)"
        case .horizontalRule: return "rule"
        case .table(let headers, let rows): return "table-\(headers.joined().hashValue)-\(rows.flatMap { $0 }.joined().hashValue)"
        }
    }
}

public actor MarkdownRenderer {
    public static let shared = MarkdownRenderer()

    private init() {}

    public func render(markdown: String, options: MarkdownRenderOptions = MarkdownRenderOptions()) async -> MarkdownRenderCache.RenderedDocument {
        if let cached = await MarkdownRenderCache.shared.get(for: markdown, options: options) {
            return cached
        }

        let document = Markdown.Document(parsing: markdown)
        var visitor = MarkdownASTVisitor()
        visitor.visit(document)
        let blocks = visitor.blocks

        var attributed = AttributedString()
        do {
            attributed = try AttributedString(markdown: markdown)
        } catch {
            attributed = AttributedString(markdown)
        }

        let rendered = MarkdownRenderCache.RenderedDocument(
            attributedContent: attributed,
            blocks: blocks,
            wordCount: calculateWordCount(markdown),
            readingTimeSeconds: calculateReadingTime(markdown)
        )

        await MarkdownRenderCache.shared.set(rendered, for: markdown, options: options)
        return rendered
    }

    @MainActor
    public func render(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown)
        } catch {
            return AttributedString(markdown)
        }
    }

    @MainActor
    public func parse(_ markdown: String) -> [MarkdownBlock] {
        let document = Markdown.Document(parsing: markdown)
        var visitor = MarkdownASTVisitor()
        visitor.visit(document)
        return visitor.blocks
    }

    private func calculateWordCount(_ text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return words.count
    }

    private func calculateReadingTime(_ text: String) -> Int {
        let words = calculateWordCount(text)
        let wpm = 200
        let minutes = Double(words) / Double(wpm)
        return max(1, Int(minutes * 60))
    }
}

private struct MarkdownASTVisitor: MarkupVisitor {
    var blocks: [MarkdownBlock] = []

    mutating func defaultVisit(_ markup: any Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Markdown.Heading) -> Any? {
        let text = heading.plainText
        blocks.append(.heading(level: heading.level, text: text))
        return nil
    }

    mutating func visitParagraph(_ paragraph: Markdown.Paragraph) -> Any? {
        let text = paragraph.plainText
        blocks.append(.paragraph(text: text))
        return nil
    }

    mutating func visitCodeBlock(_ codeBlock: Markdown.CodeBlock) -> Any? {
        blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.code))
        return nil
    }

    mutating func visitBlockQuote(_ blockQuote: Markdown.BlockQuote) -> Any? {
        let text = blockQuote.plainText
        blocks.append(.blockQuote(text: text))
        return nil
    }

    mutating func visitUnorderedList(_ unorderedList: Markdown.UnorderedList) -> Any? {
        var bulletItems: [String] = []
        var taskItems: [(checked: Bool, text: String)] = []
        var isTaskList = false

        for child in unorderedList.children {
            if let listItem = child as? Markdown.ListItem {
                if let checkbox = listItem.checkbox {
                    isTaskList = true
                    let checked = checkbox == .checked
                    taskItems.append((checked: checked, text: listItem.plainText))
                } else {
                    bulletItems.append(listItem.plainText)
                }
            }
        }

        if isTaskList {
            blocks.append(.taskList(items: taskItems))
        } else {
            blocks.append(.bulletList(items: bulletItems))
        }
        return nil
    }

    mutating func visitOrderedList(_ orderedList: Markdown.OrderedList) -> Any? {
        var items: [String] = []
        for child in orderedList.children {
            if let listItem = child as? Markdown.ListItem {
                items.append(listItem.plainText)
            }
        }
        blocks.append(.orderedList(items: items))
        return nil
    }

    mutating func visitThematicBreak(_ thematicBreak: Markdown.ThematicBreak) -> Any? {
        blocks.append(.horizontalRule)
        return nil
    }

    mutating func visitTable(_ table: Markdown.Table) -> Any? {
        var headers: [String] = []
        var rows: [[String]] = []

        for child in table.head.children {
            if let cell = child as? Markdown.Table.Cell {
                headers.append(cell.plainText)
            }
        }

        for child in table.body.children {
            if let row = child as? Markdown.Table.Row {
                var rowCells: [String] = []
                for cellChild in row.children {
                    if let cell = cellChild as? Markdown.Table.Cell {
                        rowCells.append(cell.plainText)
                    }
                }
                rows.append(rowCells)
            }
        }

        blocks.append(.table(headers: headers, rows: rows))
        return nil
    }
}

public struct MarkdownBlockListView: View {
    let blocks: [MarkdownBlock]

    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

public struct MarkdownBlockView: View {
    let block: MarkdownBlock

    public var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 12 : 6)
                .padding(.bottom, 4)

        case .paragraph(let text):
            Text(text)
                .font(.body)
                .lineSpacing(4)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(10)
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(6)
            }
            .padding(.vertical, 4)

        case .blockQuote(let text):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 4)
                Text(text)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.body)
                        Text(item)
                            .font(.body)
                    }
                }
            }
            .padding(.leading, 12)

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.body)
                        Text(item)
                            .font(.body)
                    }
                }
            }
            .padding(.leading, 12)

        case .taskList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.text) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.checked ? .blue : .secondary)
                        Text(item.text)
                            .font(.body)
                    }
                }
            }
            .padding(.leading, 6)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)

        case .table(let headers, let rows):
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ForEach(headers, id: \.self) { header in
                            Text(header)
                                .font(.body.bold())
                                .padding(8)
                                .background(Color.blue.opacity(0.12))
                        }
                    }
                    Divider()
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row, id: \.self) { cell in
                                Text(cell)
                                    .font(.body)
                                    .padding(8)
                            }
                        }
                        Divider()
                    }
                }
            }
            .border(Color.secondary.opacity(0.3))
            .padding(.vertical, 6)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        case 5: return .subheadline
        default: return .callout
        }
    }
}
