import Foundation
import SwiftUI

// Rendered Markdown viewer, adapted from Legacy's
// `SwiftCode/Views/Editor/MarkdownFileView.swift`. The destination has
// no rendered-Markdown editor surface (README V2 lists it as planned),
// so this is a real one: on macOS the Markdown is rendered through
// Foundation's `AttributedString(markdown:)`; on other platforms the
// raw text is shown with the same mode toggle. The toggle switches
// between the rendered view and the raw source.

/// View a Markdown file rendered, with a raw-source toggle.
struct MarkdownFileView: View {
    /// The Markdown source to display.
    var source: String
    /// A title for the header, such as the file name.
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
