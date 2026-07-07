import SwiftUI

struct StringLengthCounterView: View {
    @State private var input = ""

    var body: some View {
        VStack(spacing: 20) {
            TextEditor(text: $input)
                .border(Color.secondary.opacity(0.2))
                .padding()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                StatCard(label: "Characters", value: "\(input.count)")
                StatCard(label: "Words", value: "\(input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count)")
                StatCard(label: "Lines", value: "\(input.components(separatedBy: .newlines).count)")
                StatCard(label: "Characters (no spaces)", value: "\(input.replacingOccurrences(of: " ", with: "").count)")
            }
            .padding()

            Spacer()
        }
        .navigationTitle("String Length Counter")
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack {
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}
