import SwiftUI

@MainActor
struct AssistSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Model Selection", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        Picker("Default Assist Model", selection: $settings.selectedAssistModelID) {
                            ForEach(AssistModelOption.all) { model in
                                Text("\(model.displayName) (\(model.provider))")
                                    .tag(model.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("Select the primary model used for AI assistance and code generation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("About Assist", systemImage: "info.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Text("Assist allows you to use AI to help you write code, explain concepts, and perform complex refactorings.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Assist Settings")
    }
}
