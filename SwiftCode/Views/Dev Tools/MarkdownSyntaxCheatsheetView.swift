import SwiftUI

struct MDElement: Identifiable {
    let id = UUID()
    let name: String
    let syntax: String
    let preview: String
}

public struct MarkdownSyntaxCheatsheetView: View {
    private let elements = [
        MDElement(name: "Heading 1", syntax: "# Header Title", preview: "Header Title (Large scale)"),
        MDElement(name: "Heading 2", syntax: "## Section Header", preview: "Section Header (Medium scale)"),
        MDElement(name: "Bold Text", syntax: "**bold string**", preview: "Bold emphasis string"),
        MDElement(name: "Italic Text", syntax: "*italicized string*", preview: "Italicized emphasis string"),
        MDElement(name: "Bullet List", syntax: "- First item\n- Second item", preview: "• First item\n• Second item"),
        MDElement(name: "Numbered List", syntax: "1. Step one\n2. Step two", preview: "1. Step one\n2. Step two"),
        MDElement(name: "Code Block", syntax: "```swift\nlet x = 10\n```", preview: "Monospaced formatted block"),
        MDElement(name: "Hyperlink", syntax: "[Apple](https://apple.com)", preview: "Clickable text redirecting to URL"),
        MDElement(name: "Blockquote", syntax: "> Quote message", preview: "Indented block containing quoted references")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Markdown Syntax Reference", systemImage: "doc.richtext")
                    .font(.title2.bold())
                Text("Lookup syntax definitions for common markdown structural elements and components.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)

            Divider()

            List {
                HStack {
                    Text("Markdown Element").font(.caption.bold()).frame(width: 180, alignment: .leading)
                    Text("Syntax Definition").font(.caption.bold()).frame(width: 240, alignment: .leading)
                    Text("Visual Output Preview").font(.caption.bold())
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 4)

                Divider()

                ForEach(elements) { item in
                    HStack {
                        Text(item.name)
                            .font(.headline)
                            .frame(width: 180, alignment: .leading)

                        Text(item.syntax)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 240, alignment: .leading)
                            .foregroundColor(.orange)

                        Text(item.preview)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.syntax, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
