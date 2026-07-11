import SwiftUI

// MARK: - Extension Demo View

struct ExtensionDemoView: View {
    let ext: ExtensionManifest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            genericFallbackView
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var genericFallbackView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(ext.name, systemImage: ext.category.icon)
                        .font(.title2.bold())
                    Text("v\(ext.version) · By \(ext.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ext.description)
                        .font(.body)
                }
                .padding(.vertical, 8)
            } header: {
                Text("About")
            }

            Section {
                Text("EntryPoint: \(ext.entryPoint)")
                if !ext.capabilities.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Capabilities:")
                            .font(.headline)
                        ForEach(ext.capabilities, id: \.self) { capability in
                            Text("• \(capability.rawValue)")
                        }
                    }
                }
            } header: {
                Text("Technical Details")
            }
        }
        .navigationTitle(ext.name)
    }
}
