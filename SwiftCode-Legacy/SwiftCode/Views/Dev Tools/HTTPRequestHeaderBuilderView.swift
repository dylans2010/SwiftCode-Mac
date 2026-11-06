import SwiftUI

struct RequestHeaderPair: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}

public struct HTTPRequestHeaderBuilderView: View {
    @State private var headers: [RequestHeaderPair] = [
        RequestHeaderPair(key: "Content-Type", value: "application/json"),
        RequestHeaderPair(key: "Accept", value: "*/*"),
        RequestHeaderPair(key: "Authorization", value: "Bearer your_token_here")
    ]
    @State private var exportedText = ""

    private let commonKeys = ["Accept", "Accept-Encoding", "Authorization", "Cache-Control", "Content-Type", "User-Agent", "X-Requested-With"]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HTTP Request Header Builder")
                        .font(.title.bold())
                    Text("Construct, customize, and export valid Key-Value HTTP request header payload dictionaries.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Active HTTP Headers")
                            .font(.headline)

                        ForEach(headers.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                Picker("", selection: $headers[idx].key) {
                                    Text("Custom...").tag(headers[idx].key)
                                    ForEach(commonKeys, id: \.self) { commonKey in
                                        Text(commonKey).tag(commonKey)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 140)

                                TextField("Custom Key Name", text: $headers[idx].key)
                                    .textFieldStyle(.roundedBorder)

                                TextField("Value Value", text: $headers[idx].value)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    headers.remove(at: idx)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: {
                            headers.append(RequestHeaderPair(key: "", value: ""))
                        }) {
                            Label("Add Header Key", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                Button("Export Headers Dictionary") {
                    generateExport()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if !exportedText.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Exported JSON Dictionary Output")
                                .font(.headline)

                            Text(exportedText)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)

                            Button("Copy Dictionary") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(exportedText, forType: .string)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func generateExport() {
        let active = headers.filter { !$0.key.isEmpty }
        var parts: [String] = []
        for p in active {
            parts.append("  \"\(p.key)\": \"\(p.value)\"")
        }
        exportedText = "{\n" + parts.joined(separator: ",\n") + "\n}"
    }
}
