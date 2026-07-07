import SwiftUI

struct TextCaseSwapperView: View {
    @State private var input = ""
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            TextEditor(text: $input)
                .border(Color.secondary.opacity(0.2))
                .padding(.horizontal)

            HStack {
                Button("UPPERCASE") { output = input.uppercased() }
                Button("lowercase") { output = input.lowercased() }
                Button("Capitalized") { output = input.capitalized }
                Button("Swap Case") { swapCase() }
            }

            TextEditor(text: .constant(output))
                .border(Color.secondary.opacity(0.2))
                .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
        .navigationTitle("Text Case Swapper")
    }

    func swapCase() {
        output = String(input.map {
            let s = String($0)
            return s == s.uppercased() ? s.lowercased() : s.uppercased()
        })
    }
}
