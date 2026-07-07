import SwiftUI

struct ASCIIArtGeneratorView: View {
    @State private var input = "SWIFT"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            TextField("Type text...", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.title)
                .onChange(of: input) { generate() }

            ScrollView([.horizontal, .vertical]) {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color.black)
            .foregroundColor(.green)
            .cornerRadius(8)

            Button("Copy ASCII Art") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            }
        }
        .padding()
        .navigationTitle("ASCII Art Generator")
        .onAppear { generate() }
    }

    func generate() {
        // Very simple mock ASCII art generator
        output = """
         ____  _      _____ _____ _____
        / ___|| |    |_   _|  ___|_   _|
        \\___ \\| |      | | | |_    | |
         ___) | |___   | | |  _|   | |
        |____/|_____|  |_| |_|     |_|
        """
    }
}
