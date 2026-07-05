import SwiftUI

// MARK: - TypeScript Support Extension View
struct TypeScriptSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var strictMode = true
    @State private var tsconfigPath = "./tsconfig.json"
    @State private var enableJSX = true
    @State private var targetVersion = "ES2022"

    private let targets = ["ES5", "ES2015", "ES2017", "ES2019", "ES2020", "ES2022", "ESNext"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable TypeScript Support", isOn: $isEnabled)
                Toggle("Strict Mode", isOn: $strictMode)
                Toggle("Enable JSX/TSX", isOn: $enableJSX)
            } header: {
                Label("TypeScript Support", systemImage: "t.square.fill")
            }
            Section {
                HStack {
                    Text("tsconfig Path")
                    Spacer()
                    TextField("./tsconfig.json", text: $tsconfigPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                Picker("Compile Target", selection: $targetVersion) {
                    ForEach(targets, id: \.self) { t in Text(t).tag(t) }
                }
            } header: {
                Text("Compiler Options")
            }
            Section {
                Text("TypeScript and TSX syntax highlighting with inline type annotations, import resolution, and tsconfig.json awareness.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("TypeScript Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
