import Foundation
import SwiftUI
import Markdown

/// A single list item. `text` is inline-markdown source (bold/italic/code/
/// links preserved); `children` holds nested list items recursively so nested
/// lists render with indentation instead of being flattened.
public struct MarkdownListItem: Sendable, Hashable, Identifiable {
    public var id: String { text + "|" + children.map(\.id).joined(separator: "|") }
    public var text: String
    public var children: [MarkdownListItem]

    public init(text: String, children: [MarkdownListItem] = []) {
        self.text = text
        self.children = children
    }
}

public struct MarkdownTaskItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(checked)-\(text)" }
    public var checked: Bool
    public var text: String
    public var children: [MarkdownListItem]

    public init(checked: Bool, text: String, children: [MarkdownListItem] = []) {
        self.checked = checked
        self.text = text
        self.children = children
    }
}

public enum MarkdownBlock: Sendable, Identifiable {
    /// `text` is inline-markdown source, not plain text.
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String?, code: String)
    case blockQuote(text: String)
    case bulletList(items: [MarkdownListItem])
    case orderedList(items: [MarkdownListItem])
    case taskList(items: [MarkdownTaskItem])
    case horizontalRule
    case table(headers: [String], rows: [[String]])

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h-\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .codeBlock(let lang, let code): return "code-\(lang ?? "")-\(code.hashValue)"
        case .blockQuote(let text): return "quote-\(text.hashValue)"
        case .bulletList(let items): return "bullet-\(items.map(\.id).joined().hashValue)"
        case .orderedList(let items): return "ordered-\(items.map(\.id).joined().hashValue)"
        case .taskList(let items): return "task-\(items.map(\.id).joined().hashValue)"
        case .horizontalRule: return "rule"
        case .table(let headers, let rows): return "table-\(headers.joined().hashValue)-\(rows.flatMap { $0 }.joined().hashValue)"
        }
    }
}

/// Renders inline-markdown source (bold/italic/strikethrough/inline-code/
/// links) as styled text. Falls back to plain text when parsing fails.
fileprivate func inlineText(_ source: String, font: Font = .body) -> SwiftUI.Text {
    if let attributed = try? AttributedString(
        markdown: source,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
        return SwiftUI.Text(attributed).font(font)
    }
    return SwiftUI.Text(source).font(font)
}

@MainActor
public struct MarkdownParser {
    public static let shared = MarkdownParser()

    private init() {}

    public func parse(_ markdown: String) -> [MarkdownBlock] {
        MarkdownRenderer.shared.parse(sanitizedForStreaming(markdown))
    }

    /// Balances unclosed fenced code blocks so partially streamed responses
    /// still parse into blocks instead of degrading the tail into a paragraph,
    /// and strips unsafe active script/iframe HTML tags.
    /// Idempotent for complete documents.
    private func sanitizedForStreaming(_ markdown: String) -> String {
        var cleaned = markdown
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<iframe[^>]*>[\\s\\S]*?</iframe>", with: "", options: [.regularExpression, .caseInsensitive])

        let fenceCount = cleaned.components(separatedBy: "```").count - 1
        guard fenceCount % 2 == 1 else { return cleaned }
        return cleaned + "\n```"
    }

    public func render(_ markdown: String) -> AttributedString {
        MarkdownRenderer.shared.render(markdown)
    }
}

/// Reconstructs inline Markdown source from a markup subtree, preserving
/// bold/italic/strikethrough/inline-code/link formatting. The previous
/// implementation used `plainText`, which silently stripped all inline
/// formatting from rendered model output.
private func inlineMarkdownSource(of markup: any Markdown.Markup) -> String {
    switch markup {
    case let text as Markdown.Text:
        return text.string
    case let strong as Markdown.Strong:
        return "**\(strong.children.map(inlineMarkdownSource(of:)).joined())**"
    case let emphasis as Markdown.Emphasis:
        return "*\(emphasis.children.map(inlineMarkdownSource(of:)).joined())*"
    case let code as Markdown.InlineCode:
        return "`\(code.code)`"
    case let link as Markdown.Link:
        let label = link.children.map(inlineMarkdownSource(of:)).joined()
        if let dest = link.destination, !dest.isEmpty {
            return "[\(label)](\(dest))"
        }
        return label
    case let strike as Markdown.Strikethrough:
        return "~~\(strike.children.map(inlineMarkdownSource(of:)).joined())~~"
    case let image as Markdown.Image:
        // Remote images are not fetched inline; keep the alt text.
        return image.children.map(inlineMarkdownSource(of:)).joined()
    case is Markdown.SoftBreak:
        return "\n"
    case is Markdown.LineBreak:
        return "\n"
    default:
        return markup.children.map(inlineMarkdownSource(of:)).joined()
    }
}

/// Inline text of a list item, excluding nested lists (which become children).
private func listItemInlineText(_ item: Markdown.ListItem) -> String {
    item.children
        .filter { !($0 is Markdown.UnorderedList) && !($0 is Markdown.OrderedList) }
        .map { inlineMarkdownSource(of: $0) }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Recursively collects nested list items.
private func listItemChildren(_ item: Markdown.ListItem) -> [MarkdownListItem] {
    var children: [MarkdownListItem] = []
    for child in item.children {
        let nestedItems: [Markdown.ListItem]
        if let nested = child as? Markdown.UnorderedList {
            nestedItems = nested.children.compactMap { $0 as? Markdown.ListItem }
        } else if let nested = child as? Markdown.OrderedList {
            nestedItems = nested.children.compactMap { $0 as? Markdown.ListItem }
        } else {
            continue
        }
        children.append(contentsOf: nestedItems.map {
            MarkdownListItem(text: listItemInlineText($0), children: listItemChildren($0))
        })
    }
    return children
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
    typealias Result = Any?
    var blocks: [MarkdownBlock] = []

    mutating func defaultVisit(_ markup: Markup) -> Any? {
        for child in markup.children {
            _ = visit(child)
        }
        return nil
    }

    mutating func visitDocument(_ document: Markdown.Document) -> Any? {
        for child in document.children {
            _ = visit(child)
        }
        return nil
    }

    mutating func visitHeading(_ heading: Markdown.Heading) -> Any? {
        blocks.append(.heading(level: heading.level, text: inlineMarkdownSource(of: heading)))
        return nil
    }

    mutating func visitParagraph(_ paragraph: Markdown.Paragraph) -> Any? {
        let text = inlineMarkdownSource(of: paragraph)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        blocks.append(.paragraph(text: text))
        return nil
    }

    mutating func visitCodeBlock(_ codeBlock: Markdown.CodeBlock) -> Any? {
        blocks.append(.codeBlock(language: codeBlock.language, code: codeBlock.code))
        return nil
    }

    mutating func visitBlockQuote(_ blockQuote: Markdown.BlockQuote) -> Any? {
        let text = blockQuote.children.map { inlineMarkdownSource(of: $0) }.joined(separator: "\n")
        blocks.append(.blockQuote(text: text))
        return nil
    }

    mutating func visitUnorderedList(_ unorderedList: Markdown.UnorderedList) -> Any? {
        let listItems = unorderedList.children.compactMap { $0 as? Markdown.ListItem }
        var taskItems: [MarkdownTaskItem] = []
        var bulletItems: [MarkdownListItem] = []
        for item in listItems {
            let text = listItemInlineText(item)
            let children = listItemChildren(item)
            if let checkbox = item.checkbox {
                taskItems.append(MarkdownTaskItem(checked: checkbox == .checked, text: text, children: children))
            } else {
                bulletItems.append(MarkdownListItem(text: text, children: children))
            }
        }

        if !taskItems.isEmpty && bulletItems.isEmpty {
            blocks.append(.taskList(items: taskItems))
        } else {
            // Mixed or plain bullets: fold checkbox items in with a textual marker.
            var all = bulletItems
            all.append(contentsOf: taskItems.map {
                MarkdownListItem(text: ($0.checked ? "[x] " : "[ ] ") + $0.text, children: $0.children)
            })
            blocks.append(.bulletList(items: all))
        }
        return nil
    }

    mutating func visitOrderedList(_ orderedList: Markdown.OrderedList) -> Any? {
        let items = orderedList.children.compactMap { $0 as? Markdown.ListItem }.map {
            MarkdownListItem(text: listItemInlineText($0), children: listItemChildren($0))
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
                headers.append(inlineMarkdownSource(of: cell))
            }
        }

        for child in table.body.children {
            if let row = child as? Markdown.Table.Row {
                var rowCells: [String] = []
                for cellChild in row.children {
                    if let cell = cellChild as? Markdown.Table.Cell {
                        rowCells.append(inlineMarkdownSource(of: cell))
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
            inlineText(text, font: headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 12 : 6)
                .padding(.bottom, 4)

        case .paragraph(let text):
            inlineText(text)
                .lineSpacing(4)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let language {
                        Text(language.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("CODE")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                            Text("Copy")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))

                ScrollView(.horizontal) {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(Color.black.opacity(0.3))
            }
            .cornerRadius(6)
            .padding(.vertical, 4)

        case .blockQuote(let text):
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 4)
                inlineText(text)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .bulletList(let items):
            MarkdownNestedListView(items: items, ordered: false)
                .padding(.leading, 12)

        case .orderedList(let items):
            MarkdownNestedListView(items: items, ordered: true)
                .padding(.leading, 12)

        case .taskList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.checked ? .blue : .secondary)
                            inlineText(item.text)
                        }
                        if !item.children.isEmpty {
                            MarkdownNestedListView(items: item.children, ordered: false)
                                .padding(.leading, 24)
                        }
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
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            inlineText(header)
                                .fontWeight(.bold)
                                .padding(8)
                                .background(Color.blue.opacity(0.12))
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                inlineText(cell)
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

/// Recursive list view: nested items render indented under their parent
/// instead of being flattened into a single level.
public struct MarkdownNestedListView: View {
    let items: [MarkdownListItem]
    let ordered: Bool

    public init(items: [MarkdownListItem], ordered: Bool) {
        self.items = items
        self.ordered = ordered
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(.body)
                        inlineText(item.text)
                    }
                    if !item.children.isEmpty {
                        MarkdownNestedListView(items: item.children, ordered: false)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
}
