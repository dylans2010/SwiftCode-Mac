import SwiftUI

struct CodeRefactoringView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var fromText = ""
    @State private var toText = ""
    @State private var preview = ""
    @State private var parserOutput = ""

    var body: some View {
        AdvancedToolScreen(title: "Code Refactoring") {
            AdvancedToolCard(title: "Global Rename") {
                TextField("Old Symbol", text: $fromText).textFieldStyle(.roundedBorder)
                TextField("New Symbol", text: $toText).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Preview Rename") { preview = sessionStore.activeFileContent.replacingOccurrences(of: fromText, with: toText) }
                    Button("Apply Rename") { sessionStore.activeFileContent = preview }
                }
                .buttonStyle(.bordered)
            }

            AdvancedToolCard(title: "Transformations") {
                HStack {
                    Button("Extract to Function") { preview = sessionStore.activeFileContent + "\n\nfunc extractedFunction() {\n    // Extracted code\n}" }
                    Button("To async/await") { preview = sessionStore.activeFileContent.replacingOccurrences(of: "completion:", with: "async") }
                    Button("Run SwiftFormat") { runFormatter() }
                    Button("Parse (Tree-sitter)") { runTreeSitter() }
                }
                .buttonStyle(.bordered)
            }

            AdvancedToolCard(title: "Preview") {
                ScrollView { Text(preview).frame(maxWidth: .infinity, alignment: .leading).font(.caption.monospaced()) }
                    .frame(minHeight: 180)
                Button("Confirm All Changes") { sessionStore.activeFileContent = preview }
                    .buttonStyle(.borderedProminent)
            }

            if !parserOutput.isEmpty {
                AdvancedToolCard(title: "Tree-sitter Output") {
                    ScrollView {
                        Text(parserOutput)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160)
                }
            }
        }
    }

    private func runFormatter() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-format-\(UUID().uuidString).swift")
        do {
            try sessionStore.activeFileContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            preview = sessionStore.activeFileContent
            return
        }

        Task {
            do {
                _ = try await BinaryManager.shared.runSwiftFormat(at: tempURL.path)
                let updated = (try? String(contentsOf: tempURL)) ?? sessionStore.activeFileContent
                await MainActor.run { preview = updated }
            } catch {
                await MainActor.run {
                    preview = sessionStore.activeFileContent.replacingOccurrences(of: "\t", with: "    ")
                }
            }
        }
    }

    private func runTreeSitter() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-parse-\(UUID().uuidString).swift")
        do {
            try sessionStore.activeFileContent.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            parserOutput = "Unable to create temporary file for parser."
            return
        }

        Task {
            do {
                let parseResult = try await BinaryManager.shared.runTreeSitterParser(filePath: tempURL.path)
                await MainActor.run {
                    parserOutput = parseResult.mergedOutput.isEmpty ? "No parser output." : parseResult.mergedOutput
                }
            } catch {
                await MainActor.run {
                    parserOutput = "Tree-sitter unavailable: \(error.localizedDescription)"
                }
            }
        }
    }
}
