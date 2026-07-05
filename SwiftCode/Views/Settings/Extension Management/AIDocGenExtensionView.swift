import SwiftUI

// MARK: - AI Doc Generator Extension View
struct AIDocGenExtensionView: View {
    @State private var isEnabled = true
    @State private var docStyle = "docc"
    @State private var autoTrigger = false
    @State private var includeExamples = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Doc Generator", isOn: $isEnabled)
                Toggle("Auto-Trigger on New Functions", isOn: $autoTrigger)
                Toggle("Include Usage Examples", isOn: $includeExamples)
            } header: {
                Label("AI Doc Generator", systemImage: "doc.text.magnifyingglass")
            }
            Section {
                Picker("Documentation Style", selection: $docStyle) {
                    Text("Apple DocC (/// style)").tag("docc")
                    Text("Markdown").tag("markdown")
                    Text("Jazzy").tag("jazzy")
                }
            } header: {
                Text("Output Format")
            }
            Section {
                Label("Invoke via Editor → Generate Documentation", systemImage: "contextualmenu.and.cursorarrow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Usage")
            }
            Section {
                Text("Auto-generates Swift DocC documentation comments for functions, types, and properties using AI. Works best with clear function signatures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("AI Doc Generator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
