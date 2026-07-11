import Foundation
import SwiftUI

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

public struct MarkdownRenderer: Sendable {
    public static let shared = MarkdownRenderer()

    public func render(_ markdown: String) -> AttributedString {
        do {
            return try AttributedString(markdown: markdown)
        } catch {
            return AttributedString(markdown)
        }
    }

    public func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: .newlines)

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            // 1. Code Block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 2. Heading
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                if level >= 1 && level <= 6 {
                    let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: level, text: text))
                    index += 1
                    continue
                }
            }

            // 3. Blockquote
            if trimmed.hasPrefix(">") {
                let text = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                blocks.append(.blockQuote(text: text))
                index += 1
                continue
            }

            // 4. Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                index += 1
                continue
            }

            // 5. Checklist / Task List
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                var items: [(checked: Bool, text: String)] = []
                while index < lines.count {
                    let l = lines[index]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- [ ]") {
                        items.append((false, String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                        index += 1
                    } else if t.hasPrefix("- [x]") || t.hasPrefix("- [X]") {
                        items.append((true, String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces)))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.taskList(items: items))
                continue
            }

            // 6. Bullet List
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while index < lines.count {
                    let l = lines[index]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") {
                        items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else if t.hasPrefix("* ") {
                        items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else if t.hasPrefix("+ ") {
                        items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // 7. Ordered List (e.g. 1. Item)
            if let firstChar = trimmed.first, firstChar.isNumber {
                let numberPrefix = trimmed.prefix(while: { $0.isNumber })
                let rest = trimmed.dropFirst(numberPrefix.count)
                if rest.hasPrefix(". ") {
                    var items: [String] = []
                    while index < lines.count {
                        let l = lines[index]
                        let t = l.trimmingCharacters(in: .whitespaces)
                        if let numChar = t.first, numChar.isNumber {
                            let numPrefix = t.prefix(while: { $0.isNumber })
                            let r = t.dropFirst(numPrefix.count)
                            if r.hasPrefix(". ") {
                                items.append(String(r.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                                index += 1
                                continue
                            }
                        }
                        break
                    }
                    blocks.append(.orderedList(items: items))
                    continue
                }
            }

            // 8. Table (starts with '|' and has separators in the next line)
            if trimmed.hasPrefix("|") {
                let headers = trimmed.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                if index + 1 < lines.count {
                    let nextTrimmed = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    let isSeparator = nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-")

                    if isSeparator {
                        var rows: [[String]] = []
                        index += 2 // skip header and separator

                        while index < lines.count {
                            let rLine = lines[index].trimmingCharacters(in: .whitespaces)
                            if rLine.hasPrefix("|") {
                                let rowCells = rLine.components(separatedBy: "|")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                                if !rowCells.isEmpty {
                                    rows.append(rowCells)
                                }
                                index += 1
                            } else {
                                break
                            }
                        }
                        blocks.append(.table(headers: headers, rows: rows))
                        continue
                    }
                }
            }

            // 9. Standard Paragraph
            blocks.append(.paragraph(text: trimmed))
            index += 1
        }

        return blocks
    }
}

// MARK: - Reusable Rendering Components

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
            Text(AttributedString(MarkdownRenderer.shared.render(text)))
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level == 1 ? 12 : 6)
                .padding(.bottom, 4)

        case .paragraph(let text):
            Text(AttributedString(MarkdownRenderer.shared.render(text)))
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
                Text(AttributedString(MarkdownRenderer.shared.render(text)))
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
                        Text(AttributedString(MarkdownRenderer.shared.render(item)))
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
                        Text(AttributedString(MarkdownRenderer.shared.render(item)))
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
                        Text(AttributedString(MarkdownRenderer.shared.render(item.text)))
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
