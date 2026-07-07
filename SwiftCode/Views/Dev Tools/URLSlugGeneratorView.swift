import SwiftUI

struct URLSlugGeneratorView: View {
    @State private var input = "Hello World! This is a Test."
    @State private var slug = "hello-world-this-is-a-test"

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter title...", text: $input)
                .textFieldStyle(.roundedBorder)
                .onChange(of: input) { generate() }

            HStack {
                Text("Slug:")
                    .font(.headline)
                Text(slug)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(slug, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
        .navigationTitle("URL Slug Generator")
    }

    func generate() {
        slug = input.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
