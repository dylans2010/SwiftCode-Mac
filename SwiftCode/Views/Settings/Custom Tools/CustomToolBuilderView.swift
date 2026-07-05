import SwiftUI

struct CustomToolBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registry = CustomToolRegistry.shared

    // Basic info
    @State private var toolName = ""
    @State private var toolDescription = ""

    // HTTP configuration
    @State private var httpMethod: HTTPMethod = .post
    @State private var endpoint = ""
    @State private var headers: [HeaderEntry] = []
    @State private var bodyTemplate = ""

    // Parameters
    @State private var parameters: [CustomToolParameter] = []

    // Response
    @State private var expectedOutput = ""
    @State private var responseParsingHint = ""

    // UI state
    @State private var activeTab: Tab = .info
    @State private var showHeaderEntry = false
    @State private var newHeaderKey = ""
    @State private var newHeaderValue = ""
    @State private var showParamEntry = false
    @State private var isSaved = false
    @State private var showValidation = false

    enum Tab: String, CaseIterable {
        case info       = "Info"
        case http       = "HTTP"
        case params     = "Parameters"
        case response   = "Response"
    }

    enum HTTPMethod: String, CaseIterable {
        case get    = "GET"
        case post   = "POST"
        case put    = "PUT"
        case patch  = "PATCH"
        case delete = "DELETE"
    }

    struct HeaderEntry: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var isValid: Bool {
        !toolName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !endpoint.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                Picker("Tab", selection: $activeTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        switch activeTab {
                        case .info:     infoTab
                        case .http:     httpTab
                        case .params:   paramsTab
                        case .response: responseTab
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Advanced Tool Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isValid { saveTool() }
                        else { showValidation = true }
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Validation Error", isPresented: $showValidation) {
                Button("OK") {}
            } message: {
                Text("Tool name and endpoint URL are required.")
            }
            .sheet(isPresented: $showHeaderEntry) {
                headerEntrySheet
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                labeledField("Tool Name", placeholder: "e.g. Fetch Weather", text: $toolName)
                labeledTextEditor("Description", placeholder: "What does this tool do?", text: $toolDescription)
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - HTTP Tab

    private var httpTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Method + Endpoint
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HTTP Method")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Method", selection: $httpMethod) {
                        ForEach(HTTPMethod.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                labeledField("Endpoint URL", placeholder: "Enter Endpoint URL", text: $endpoint)
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            // Headers
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Headers").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Button {
                        newHeaderKey = ""
                        newHeaderValue = ""
                        showHeaderEntry = true
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                if headers.isEmpty {
                    Text("No Custom Headers").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(headers) { h in
                        HStack {
                            Text(h.key).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            Text(":").foregroundStyle(.secondary).font(.caption)
                            Text(h.value).font(.caption).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            // Body Template
            VStack(alignment: .leading, spacing: 8) {
                Text("Request Body Template (JSON)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $bodyTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.3))
                    .frame(minHeight: 120)
                    .cornerRadius(8)
                Text("Use {{paramName}} placeholders. The agent will substitute real values.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Params Tab

    private var paramsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parameters").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button {
                    parameters.append(CustomToolParameter())
                } label: {
                    Label("Add", systemImage: "plus.circle.fill").foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }

            if parameters.isEmpty {
                Text("No Parameters Defined").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach($parameters) { $param in
                    ParameterEditorRow(param: $param, onDelete: {
                        parameters.removeAll { $0.id == param.id }
                    })
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Response Tab

    private var responseTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                labeledTextEditor("Expected Output", placeholder: "Describe what a successful response looks like…", text: $expectedOutput)
                labeledField("Response Parsing Hint", placeholder: "e.g. Extract .data.temperature as Double", text: $responseParsingHint)
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Header Entry Sheet

    private var headerEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Header") {
                    TextField("Key (e.g. Authorization)", text: $newHeaderKey)
                        .autocorrectionDisabled()
                    TextField("Value (e.g. Bearer token)", text: $newHeaderValue)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showHeaderEntry = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !newHeaderKey.isEmpty {
                            headers.append(HeaderEntry(key: newHeaderKey, value: newHeaderValue))
                        }
                        showHeaderEntry = false
                    }
                    .disabled(newHeaderKey.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Helpers

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private func labeledTextEditor(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.body).foregroundStyle(.tertiary).padding(4)
                }
                TextEditor(text: text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80)
            }
        }
    }

    private func buildDescription() -> String {
        var parts: [String] = []
        if !toolDescription.isEmpty { parts.append(toolDescription) }
        if !headers.isEmpty {
            let headerLines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            parts.append("Headers:\n\(headerLines)")
        }
        if !bodyTemplate.isEmpty { parts.append("Body:\n\(bodyTemplate)") }
        return parts.joined(separator: "\n\n")
    }

    private func saveTool() {
        let fullEndpoint = "\(httpMethod.rawValue) \(endpoint)"
        let combinedDescription = buildDescription()

        registry.connections.append(CustomAgentConnection(
            name: toolName,
            toolDescription: combinedDescription,
            apiEndpoint: fullEndpoint,
            parameters: parameters,
            expectedOutput: expectedOutput
        ))

        isSaved = true
        dismiss()
    }
}

// MARK: - Parameter Editor Row

struct ParameterEditorRow: View {
    @Binding var param: CustomToolParameter
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Parameter Name", text: $param.name)
                    .font(.subheadline.weight(.semibold))
                    .autocorrectionDisabled()
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Picker("Type", selection: $param.type) {
                    Text("string").tag("string")
                    Text("number").tag("number")
                    Text("boolean").tag("boolean")
                    Text("object").tag("object")
                    Text("array").tag("array")
                }
                .pickerStyle(.menu)
                .font(.caption)
                Toggle("Required", isOn: $param.required)
                    .font(.caption)
                    .labelsHidden()
                Text(param.required ? "Required" : "Optional")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TextField("Description", text: $param.paramDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .autocorrectionDisabled()
        }
        .padding()
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
