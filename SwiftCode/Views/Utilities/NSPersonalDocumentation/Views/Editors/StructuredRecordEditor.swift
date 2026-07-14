import SwiftUI

public struct StructuredRecordEditor: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    // Custom Interactive State Variables
    @State private var recordSchemaType = "Generic Record"
    @State private var author = ""
    @State private var serializationFormat = "JSON"
    @State private var validationStatus = "Valid"
    @State private var dataSensitivity = "Internal-Only"

    // Key-Value Schema Model State
    @State private var schemaKey = ""
    @State private var schemaValue = ""
    @State private var schemaType = "String"
    @State private var addedSchemaItems: [SchemaItem] = []

    struct SchemaItem: Identifiable, Hashable {
        let id = UUID()
        var key: String
        var value: String
        var type: String
    }

    public init(coordinator: PersonalDocumentationCoordinator, documentID: UUID?) {
        self.coordinator = coordinator
        self.documentID = documentID
    }

    public var body: some View {
        BaseEditorView(
            coordinator: coordinator,
            kind: .structuredRecord,
            documentID: documentID,
            specializedToolbar: {
                HStack(spacing: 6) {
                    Button {
                        insertKeyValueTable()
                    } label: {
                        Label("KV Catalog", systemImage: "tablecells.fill")
                    }
                    .help("Insert structured key-value table matrix")

                    Button {
                        insertSerializationPreview()
                    } label: {
                        Label("Code Block", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Insert serialized payload code block preview")
                }
            },
            specializedMetadata: {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Schema:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("JSON/YAML class", text: $recordSchemaType)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                            Text("Author:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("Name", text: $author)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        GridRow {
                            Text("Format:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $serializationFormat) {
                                Text("JSON").tag("JSON")
                                Text("YAML").tag("YAML")
                                Text("XML").tag("XML")
                            }
                            .controlSize(.small)

                            Text("Sensitivity:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $dataSensitivity) {
                                Text("Public").tag("Public")
                                Text("Internal").tag("Internal-Only")
                                Text("Conf").tag("Confidential/PII")
                            }
                            .controlSize(.small)
                        }

                        GridRow {
                            Text("Validation:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Picker("", selection: $validationStatus) {
                                Text("Valid").tag("Valid")
                                Text("Warning").tag("Warning")
                                Text("Pending").tag("Pending Audit")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                            .gridCellColumns(3)
                        }
                    }

                    Divider().padding(.vertical, 4)

                    // SCHEMA PROPERTY BUILDER
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCHEMA PROPERTY CATALOG BUILDER")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                            GridRow {
                                TextField("Key (e.g. username)", text: $schemaKey)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Picker("", selection: $schemaType) {
                                    Text("String").tag("String")
                                    Text("Int").tag("Integer")
                                    Text("Bool").tag("Boolean")
                                }
                                .controlSize(.small)
                            }
                            GridRow {
                                TextField("Sample Value", text: $schemaValue)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .gridCellColumns(2)
                            }
                        }

                        Button("Add Schema Entry") {
                            addSchemaItem()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        // Added schema items catalog list
                        if !addedSchemaItems.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(addedSchemaItems) { item in
                                    HStack {
                                        Text(item.key)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        Text(":")
                                        Text(item.value)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text("(\(item.type))")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                        Button {
                                            addedSchemaItems.removeAll(where: { $0.id == item.id })
                                        } label: {
                                            Image(systemName: "xmark").font(.system(size: 8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            },
            validationMessage: nil
        )
    }

    private func addSchemaItem() {
        let key = schemaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let item = SchemaItem(
            key: key,
            value: schemaValue.isEmpty ? "null" : schemaValue,
            type: schemaType
        )
        addedSchemaItems.append(item)
        schemaKey = ""
        schemaValue = ""
    }

    private func insertKeyValueTable() {
        var kvMarkdown = "| Parameter / Key | Value | Datatype / Validation |\n| :--- | :--- | :--- |\n"
        if addedSchemaItems.isEmpty {
            kvMarkdown += "| Record ID | `REC_93041` | UUID |\n| Last Evaluated | `\(Date().formatted(date: .numeric, time: .shortened))` | DateTime |\n"
        } else {
            for item in addedSchemaItems {
                let quote = item.type == "String" ? "`\"\(item.value)\"`" : "`\(item.value)`"
                kvMarkdown += "| \(item.key) | \(quote) | \(item.type) |\n"
            }
        }

        let template = """

        ### Structured Key-Value Record: \(recordSchemaType)

        **Author:** `\(author.isEmpty ? "Unknown" : author)`
        **Serialization Format:** `\(serializationFormat)`
        **Data Sensitivity:** `\(dataSensitivity)`
        **Validation Status:** `\(validationStatus)`

        \(kvMarkdown)
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": template]
        )
    }

    private func insertSerializationPreview() {
        var bodyText = ""
        if serializationFormat == "JSON" {
            bodyText = "{\n  \"schema_type\": \"\(recordSchemaType)\",\n"
            if addedSchemaItems.isEmpty {
                bodyText += "  \"record_id\": \"REC_93041\"\n"
            } else {
                var lines: [String] = []
                for item in addedSchemaItems {
                    let valStr = item.type == "String" ? "\"\(item.value)\"" : item.value
                    lines.append("  \"\(item.key)\": \(valStr)")
                }
                bodyText += lines.joined(separator: ",\n") + "\n"
            }
            bodyText += "}"
        } else if serializationFormat == "YAML" {
            bodyText = "schema_type: \"\(recordSchemaType)\"\n"
            if addedSchemaItems.isEmpty {
                bodyText += "record_id: \"REC_93041\"\n"
            } else {
                for item in addedSchemaItems {
                    bodyText += "\(item.key): \(item.value)\n"
                }
            }
        } else {
            bodyText = "<record>\n  <schema_type>\(recordSchemaType)</schema_type>\n"
            if addedSchemaItems.isEmpty {
                bodyText += "  <record_id>REC_93041</record_id>\n"
            } else {
                for item in addedSchemaItems {
                    bodyText += "  <\(item.key)>\(item.value)</\(item.key)>\n"
                }
            }
            bodyText += "</record>"
        }

        let codeBlock = """

        #### Serialized Mock Payload (\(serializationFormat))
        ```\(serializationFormat.lowercased())
        \(bodyText)
        ```
        """
        NotificationCenter.default.post(
            name: NSNotification.Name("InsertEditorText"),
            object: nil,
            userInfo: ["text": codeBlock]
        )
    }
}
