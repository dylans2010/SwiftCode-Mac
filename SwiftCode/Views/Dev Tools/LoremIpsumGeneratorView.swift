import SwiftUI

struct LoremIpsumGeneratorView: View {
    @State private var paragraphs = 3
    @State private var result = ""

    let baseText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Stepper("Paragraphs: \(paragraphs)", value: $paragraphs, in: 1...20)
                Spacer()
                Button("Generate") { generate() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.top, .horizontal])

            TextEditor(text: .constant(result))
                .font(.body)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding([.bottom, .horizontal])
        }
        .navigationTitle("Lorem Ipsum Generator")
        .onAppear { generate() }
    }

    func generate() {
        result = Array(repeating: baseText, count: paragraphs).joined(separator: "\n\n")
    }
}
