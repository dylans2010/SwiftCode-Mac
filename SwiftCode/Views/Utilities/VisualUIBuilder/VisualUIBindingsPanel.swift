import SwiftUI

/// Panel configuring state properties, local @State bindings, Action hooks, and Navigation trigger routing.
public struct VisualUIBindingsPanel: View {
    @Bindable var document: VisualUIDocument
    @State private var newVariableName = ""
    @State private var newVariableType = "String"

    public var body: some View {
        VStack(spacing: 0) {
            Text("STATE BINDINGS & NAVIGATION")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Local variables section
                    GroupBox("Local @State Declarations") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("isLoggedIn, username...", text: $newVariableName)
                                    .textFieldStyle(.roundedBorder)

                                Picker("", selection: $newVariableType) {
                                    Text("String").tag("String")
                                    Text("Bool").tag("Bool")
                                    Text("Int").tag("Int")
                                }
                                .frame(width: 80)

                                Button {
                                    addStateVariable()
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.bordered)
                                .disabled(newVariableName.isEmpty)
                            }

                            Divider()

                            // Retrieve existing custom state declarations from document
                            let bindings = listExistingBindings()
                            if bindings.isEmpty {
                                Text("No local @State variables declared.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(bindings, id: \.self) { variable in
                                    HStack {
                                        Image(systemName: "character.textbox")
                                            .foregroundColor(.purple)
                                        Text("@State var \(variable)")
                                            .font(.caption.monospaced())
                                        Spacer()
                                        Button {
                                            removeStateVariable(variable)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Element Bindings Map
                    if let selectedID = document.scene.selectedNodeIDs.first,
                       let node = document.scene.findNode(byID: selectedID) {
                        GroupBox("Selection Bindings") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Bind '\(node.name)' value to dynamic variable:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                let declaredVars = listExistingBindings().map { $0.components(separatedBy: " : ").first ?? "" }
                                Picker("Bind Property:", selection: Binding(
                                    get: { node.properties["boundVariable"] ?? "None" },
                                    set: { node.properties["boundVariable"] = $0 }
                                )) {
                                    Text("None").tag("None")
                                    ForEach(declaredVars, id: \.self) { variable in
                                        Text(variable).tag(variable)
                                    }
                                }
                            }
                        }

                        // Navigation Route section
                        VisualUINavigationPanel(document: document, node: node)
                    }
                }
                .padding(8)
            }
        }
    }

    private func listExistingBindings() -> [String] {
        // Simple serialization of state variables inside scene properties
        let variablesString = document.scene.artboards.first?.rootNode.properties["declaredStateVariables"] ?? ""
        if variablesString.isEmpty { return [] }
        return variablesString.components(separatedBy: ",")
    }

    private func addStateVariable() {
        document.checkpoint()
        let cleanName = newVariableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        var current = listExistingBindings()
        let fullVar = "\(cleanName) : \(newVariableType)"
        if !current.contains(fullVar) {
            current.append(fullVar)
            document.scene.artboards.first?.rootNode.properties["declaredStateVariables"] = current.joined(separator: ",")
            VisualUISettings.shared.addLog("Declared local state variable @State var \(fullVar)")
        }
        newVariableName = ""
    }

    private func removeStateVariable(_ variable: String) {
        document.checkpoint()
        var current = listExistingBindings()
        current.removeAll(where: { $0 == variable })
        document.scene.artboards.first?.rootNode.properties["declaredStateVariables"] = current.joined(separator: ",")
        VisualUISettings.shared.addLog("Removed state variable: \(variable)")
    }
}
