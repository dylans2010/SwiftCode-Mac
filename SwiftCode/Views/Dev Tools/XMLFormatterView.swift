import SwiftUI

struct XMLFormatterView: View {
    @State private var input = "<root><user id=\"1\"><name>John Doe</name><email>john@example.com</email></user></root>"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Format XML") { format() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.top, .horizontal])

            VStack(alignment: .leading) {
                Text("Input")
                    .font(.headline)
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Output")
                    .font(.headline)
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("XML Formatter")
        .onAppear { format() }
    }

    func format() {
        // Mock XML formatter using simple string replacement for indentation
        var formatted = input
            .replacingOccurrences(of: "><", with: ">\n<")

        output = formatted
    }
}
