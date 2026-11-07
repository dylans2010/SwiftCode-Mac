import Foundation
import SwiftUI

struct MarkdownFileView: View {
    var source: String
    var title: String

    @Environment(\.colorScheme) private var scheme
    @State private var showRaw = false
    @State private var rendered: AttributedString?
    @State private var renderError: String?

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: title).font(ShellFonts.rowBold).lineLimit(1).truncationMode(.middle)
                Spacer()
                Picker("Mode", selection: $showRaw) {
                    Text("Rendered").tag(false)
                    Text("Raw").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(10)
            Hairline(color: c.separator)
            ScrollView {
                if showRaw {
                    Text(verbatim: source)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                } else if let rendered {
                    Text(rendered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Could not render this Markdown.")
                            .font(ShellFonts.rowBold)
                        Text(verbatim: renderError ?? "Rendering is unavailable on this platform; switch to Raw to read the source.")
                            .font(ShellFonts.small)
                            .foregroundStyle(c.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
        }
        .onAppear { render() }
        .onChange(of: source) { _, _ in render() }
    }

    private func render() {
#if os(macOS)
        do {
            rendered = try AttributedString(
                markdown: source,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            renderError = nil
        } catch {
            rendered = nil
            renderError = error.localizedDescription
        }
#else
        rendered = nil
        renderError = nil
#endif
    }
}
