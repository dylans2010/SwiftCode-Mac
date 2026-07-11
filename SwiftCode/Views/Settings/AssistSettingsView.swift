import SwiftUI

@MainActor
struct AssistSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Default Assist Model", selection: $settings.selectedAssistModelID) {
                    ForEach(AssistModelOption.all) { model in
                        Text("\(model.displayName) (\(model.provider))")
                            .tag(model.id)
                    }
                }
            } header: {
                Text("Model Selection")
            } footer: {
                Text("Select the primary model used for AI assistance and code generation.")
            }

            Section {
                Text("Assist allows you to use AI to help you write code, explain concepts, and perform complex refactorings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About Assist")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Assist Settings")
    }
}
