import SwiftUI

struct DatabaseSchemaGenerator: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var tables: [DatabaseTable] = []
    @State private var selectedTable = ""
    @State private var modelType = "SwiftData"
    @State private var generatedCode = ""
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            GroupBox("Generate Swift APIs") {
                HStack {
                    Picker("Table Source", selection: $selectedTable) {
                        ForEach(tables) { t in
                            Text(t.name).tag(t.name)
                        }
                    }

                    Picker("Framework Target", selection: $modelType) {
                        Text("SwiftData").tag("SwiftData")
                        Text("Codable Model").tag("Codable")
                        Text("Repository Class").tag("Repository")
                    }

                    Button("Generate Code") {
                        generateCode()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }
            .padding()

            Divider()

            if !generatedCode.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Generated Code Outputs")
                            .font(.headline)
                        Spacer()
                        Button(action: copyToClipboard) {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    }

                    ScrollView {
                        Text(generatedCode)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("Generate Apple Code", systemImage: "swift", description: Text("Generate complete production SwiftData, Codable, or Repository source files mapping table schemas."))
            }
        }
        .onAppear {
            loadTables()
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        Task {
            if let t = try? DatabaseManager.shared.fetchSQLiteTables(filePath: path) {
                tables = t
                selectedTable = t.first?.name ?? ""
            }
        }
    }

    private func generateCode() {
        guard let table = tables.first(where: { $0.name == selectedTable }) else { return }

        let structName = table.name.capitalized.replacingOccurrences(of: "_", with: "")

        if modelType == "SwiftData" {
            var code = "import Foundation\nimport SwiftData\n\n@Model\npublic final class \(structName) {\n"
            for col in table.columns {
                let sType = col.type.contains("INT") ? "Int" : col.type.contains("REAL") ? "Double" : "String"
                if col.isPrimaryKey {
                    code += "    @Attribute(.unique) public var id: \(sType)\n"
                } else {
                    code += "    public var \(col.name): \(sType)\n"
                }
            }
            code += "\n    public init("
            let initArgs = table.columns.map { col -> String in
                let sType = col.type.contains("INT") ? "Int" : col.type.contains("REAL") ? "Double" : "String"
                return "\(col.name): \(sType)"
            }.joined(separator: ", ")
            code += initArgs + ") {\n"
            for col in table.columns {
                code += "        self.\(col.name) = \(col.name)\n"
            }
            code += "    }\n}"
            generatedCode = code
        } else if modelType == "Codable" {
            var code = "import Foundation\n\npublic struct \(structName): Codable, Identifiable, Hashable {\n"
            for col in table.columns {
                let sType = col.type.contains("INT") ? "Int" : col.type.contains("REAL") ? "Double" : "String"
                code += "    public var \(col.name): \(sType)\n"
            }
            code += "}"
            generatedCode = code
        } else {
            // Repository class
            var code = "import Foundation\n\npublic final class \(structName)Repository {\n"
            code += "    private let databasePath: String\n\n"
            code += "    public init(databasePath: String) {\n"
            code += "        self.databasePath = databasePath\n"
            code += "    }\n\n"
            code += "    public func fetchAll() async throws -> [\(structName)] {\n"
            code += "        // Implementation\n"
            code += "        return []\n"
            code += "    }\n}"
            generatedCode = code
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedCode, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
