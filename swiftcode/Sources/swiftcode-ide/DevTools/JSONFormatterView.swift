import SwiftUI

struct JSONFormatterView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var indentation = 4

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Picker("Indentation", selection: $indentation) {
                    Text("2 Spaces").tag(2)
                    Text("4 Spaces").tag(4)
                    Text("Tabs").tag(0)
                }
                .frame(width: 150)

                Spacer()

                Button("Format") { format() }
                Button("Minify") { minify() }
            }
            .padding([.top, .horizontal])

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Input")
                        .font(.headline)
                    TextEditor(text: $input)
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading) {
                    Text("Output")
                        .font(.headline)
                    TextEditor(text: .constant(output))
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("JSON Formatter")
    }

    func format() {
        guard let data = input.data(using: .utf8) else { return }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let options: JSONSerialization.WritingOptions = .prettyPrinted
            let outputData = try JSONSerialization.data(withJSONObject: json, options: options)
            output = String(data: outputData, encoding: .utf8) ?? ""

            if indentation == 2 {
                output = output.replacingOccurrences(of: "    ", with: "  ")
            } else if indentation == 0 {
                output = output.replacingOccurrences(of: "    ", with: "\t")
            }
        } catch {
            output = "Error: \(error.localizedDescription)"
        }
    }

    func minify() {
        guard let data = input.data(using: .utf8) else { return }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let outputData = try JSONSerialization.data(withJSONObject: json, options: [])
            output = String(data: outputData, encoding: .utf8) ?? ""
        } catch {
            output = "Error: \(error.localizedDescription)"
        }
    }
}
