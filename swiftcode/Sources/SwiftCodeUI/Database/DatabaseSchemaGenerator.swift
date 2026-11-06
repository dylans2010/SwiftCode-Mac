import AppKit
import SwiftUI
import SwiftCodeCloud
import UniformTypeIdentifiers

/// Generates Swift model code from a table's schema.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseSchemaGenerator.swift`.
///
/// Changes over Legacy, all recorded here:
///
/// - Tables come from `SQLiteExplorerModel` (via
///   `DatabaseViewSQLite`), not Legacy's `DatabaseManager`, and
///   only while the active connection is SQLite. Remote providers
///   have no schema driver in this package for this view; Legacy
///   silently showed nothing for them, and this port does the same
///   — but the empty state says so instead of looking broken.
/// - "Save to Project" used Legacy's `ProjectSessionStore`, which
///   does not exist in the destination. It now opens a save panel
///   and writes the generated file where the user chooses. The
///   generated code itself is unchanged in kind (SwiftData,
///   Codable, Repository, JSON Schema); only the Repository
///   template's fetch call changed, from Legacy's
///   `DatabaseManager.shared.executeSQLiteQuery` (which no longer
///   exists in that form) to the destination's
///   `SQLiteExplorerModel`, so the generated repository is real
///   code against a type that exists in this package.
/// - The Swift type mapping is Legacy's verbatim (INT → Int, REAL
///   → Double, everything else → String).
/// - Legacy's `liquidGlass` group-box style is gone (SwiftCodeUI
///   has no such modifier); the default group-box style is used.
@MainActor
struct DatabaseSchemaGenerator: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var tables: [DatabaseTable] = []
    @State private var selectedTable = ""
    @State private var modelType = "SwiftData" // SwiftData, Codable, Repository, JSONSchema
    @State private var generatedCode = ""
    @State private var copied = false

    // Custom configurations
    @State private var customClassName = ""
    @State private var targetNamespace = "AppModel"
    @State private var logMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            GroupBox("Generate Swift APIs & Model Layers") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Picker("Table Source", selection: $selectedTable) {
                            ForEach(tables) { t in
                                Text(t.name).tag(t.name)
                            }
                        }
                        .onChange(of: selectedTable) { _, newValue in
                            customClassName = newValue.capitalized.replacingOccurrences(of: "_", with: "")
                        }

                        Picker("Framework Target", selection: $modelType) {
                            Text("SwiftData Model Entity").tag("SwiftData")
                            Text("Codable Model Struct").tag("Codable")
                            Text("Repository DB Wrapper").tag("Repository")
                            Text("JSON Schema definition").tag("JSONSchema")
                        }

                        Button("Generate Code") {
                            generateCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedTable.isEmpty)
                    }

                    HStack(spacing: 16) {
                        TextField("Class Name Override", text: $customClassName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)

                        TextField("Target Namespace / Module", text: $targetNamespace)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 250)
                    }

                    if tables.isEmpty {
                        Text("No tables loaded — code generation needs the active SQLite connection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

                        Button(action: saveToProjectFiles) {
                            Label("Save to File…", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        Button(action: copyToClipboard) {
                            Label(copied ? "Copied" : "Copy to Clipboard", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !logMessage.isEmpty {
                        Text(logMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }

                    ScrollView {
                        Text(generatedCode)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(8)
                            .textSelection(.enabled)
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
        .onChange(of: connManager.activeConnection) { _, _ in
            loadTables()
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else {
            tables = []
            selectedTable = ""
            return
        }
        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                tables = try DatabaseViewSQLite.fetchTables(explorer)
                selectedTable = tables.first?.name ?? ""
                customClassName = selectedTable.capitalized.replacingOccurrences(of: "_", with: "")
            } catch {
                tables = []
            }
        }
    }

    private func generateCode() {
        guard let table = tables.first(where: { $0.name == selectedTable }) else { return }

        let structName = customClassName.isEmpty ? table.name.capitalized.replacingOccurrences(of: "_", with: "") : customClassName
        logMessage = ""

        if modelType == "SwiftData" {
            var code = "import Foundation\nimport SwiftData\n\n// Target Module: \(targetNamespace)\n\n@Model\npublic final class \(structName) {\n"
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
            var code = "import Foundation\n\n// Target Module: \(targetNamespace)\n\npublic struct \(structName): Codable, Identifiable, Hashable {\n"
            var primaryColName = "id"
            for col in table.columns {
                let sType = col.type.contains("INT") ? "Int" : col.type.contains("REAL") ? "Double" : "String"
                code += "    public var \(col.name): \(sType)\n"
                if col.isPrimaryKey { primaryColName = col.name }
            }
            if primaryColName != "id" {
                code += "\n    public var id: String { String(\(primaryColName)) }\n"
            }
            code += "}"
            generatedCode = code
        } else if modelType == "Repository" {
            // Repository class, fetching through SQLiteExplorerModel.
            var code = "import Foundation\n\n// Target Module: \(targetNamespace)\n\npublic final class \(structName)Repository {\n"
            code += "    private let databasePath: String\n\n"
            code += "    public init(databasePath: String) {\n"
            code += "        self.databasePath = databasePath\n"
            code += "    }\n\n"
            code += "    @MainActor\n"
            code += "    public func fetchAll() async throws -> [\(structName)] {\n"
            code += "        let explorer = try SQLiteExplorerModel(path: databasePath)\n"
            code += "        let result = try explorer.run(sql: \"SELECT * FROM \(table.name);\")\n"
            code += "        return result.rows.map { cells in\n"
            code += "            var row: [String: String] = [:]\n"
            code += "            for (index, column) in result.columns.enumerated() where index < cells.count {\n"
            code += "                row[column] = cells[index]\n"
            code += "            }\n"
            code += "            return \(structName)(\n"
            let initParams = table.columns.map { col -> String in
                let sType = col.type.contains("INT") ? "Int" : col.type.contains("REAL") ? "Double" : "String"
                if sType == "Int" {
                    return "                \(col.name): Int(row[\"\(col.name)\"] ?? \"0\") ?? 0"
                } else if sType == "Double" {
                    return "                \(col.name): Double(row[\"\(col.name)\"] ?? \"0.0\") ?? 0.0"
                } else {
                    return "                \(col.name): row[\"\(col.name)\"] ?? \"\""
                }
            }.joined(separator: ",\n")
            code += initParams + "\n"
            code += "            )\n"
            code += "        }\n"
            code += "    }\n}"
            generatedCode = code
        } else {
            // JSON Schema Definition
            var code = "{\n  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n"
            code += "  \"title\": \"\(structName)\",\n"
            code += "  \"type\": \"object\",\n"
            code += "  \"properties\": {\n"
            var propsList: [String] = []
            for col in table.columns {
                let typeStr = col.type.contains("INT") ? "integer" : col.type.contains("REAL") ? "number" : "string"
                propsList.append("    \"\(col.name)\": { \"type\": \"\(typeStr)\" }")
            }
            code += propsList.joined(separator: ",\n") + "\n"
            code += "  },\n"
            let requiredList = table.columns.filter { !$0.isNullable && !$0.isAutoIncrement }.map { "\"\($0.name)\"" }
            code += "  \"required\": [ " + requiredList.joined(separator: ", ") + " ]\n"
            code += "}"
            generatedCode = code
        }
    }

    private func saveToProjectFiles() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(customClassName.isEmpty ? selectedTable : customClassName).swift"
        panel.allowedContentTypes = [UTType(filenameExtension: "swift")].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try generatedCode.write(to: url, atomically: true, encoding: .utf8)
            logMessage = "Saved generated file to \(url.path)"
        } catch {
            logMessage = "Failed writing file: \(error.localizedDescription)"
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
