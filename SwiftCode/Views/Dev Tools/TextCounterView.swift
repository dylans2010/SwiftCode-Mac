import SwiftUI

struct TextCounterView: View {
    @State private var input = ""

    var body: some View {
        VStack(spacing: 20) {
            TextEditor(text: $input)
                .font(.body)
                .padding(8)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack(spacing: 30) {
                StatView(label: "Characters", value: "\(input.count)")
                StatView(label: "Words", value: "\(input.split { $0.isWhitespace }.count)")
                StatView(label: "Lines", value: "\(input.components(separatedBy: .newlines).filter { !$0.isEmpty }.count)")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
        .navigationTitle("Text Counter")
    }
}

struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
