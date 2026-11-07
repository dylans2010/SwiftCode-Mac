import Foundation
import SwiftUI
import YcodeAssistant
import YcodeIDECore

struct ComposioSettingsView: View {
    static let secretAccount = "composio.api-key"

    @Environment(\.colorScheme) private var scheme
    @State private var hasKey = false
    @State private var keyInput = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingDeleteConfirm = false

    private var store: SecretStore { CodingAssistantServices.shared.store }

    var body: some View {
        let c = ShellColors(scheme)
        VStack(alignment: .leading, spacing: 10) {
            Text("Composio").font(ShellFonts.rowBold)
            Text("Composio lets the assistant call third-party app actions through the use_composio tool. The key is stored in the secret store and is never shown after saving. Without a key here, the tool falls back to the COMPOSIO_API_KEY environment variable or the Composio CLI login.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            HStack(spacing: 8) {
                Label(
                    hasKey ? "API key saved" : "No API key saved",
                    systemImage: hasKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(ShellFonts.small)
                    .foregroundStyle(hasKey ? .green : .red)
                Spacer()
                if hasKey {
                    Button("Delete Key", role: .destructive) { showingDeleteConfirm = true }
                }
            }
            SecureField("Composio API key", text: $keyInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Key") { saveKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(ShellFonts.small)
                    .foregroundStyle(statusIsError ? .red : .green)
            }
            Spacer()
        }
        .padding(12)
        .onAppear { refresh() }
        .alert("Delete the Composio API key?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The key will be removed from the secret store. The use_composio tool will then fall back to the environment variable or the Composio CLI login.")
        }
    }

    private func refresh() {
        hasKey = (try? store.readString(Self.secretAccount))?.isEmpty == false
    }

    private func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try store.write(Data(key.utf8), for: Self.secretAccount)
            keyInput = ""
            statusIsError = false
            statusMessage = "Composio API key saved."
            refresh()
        } catch {
            statusIsError = true
            statusMessage = "Could not save key: \(error.localizedDescription)"
        }
    }

    private func deleteKey() {
        do {
            try store.delete(Self.secretAccount)
            statusIsError = false
            statusMessage = "Composio API key deleted."
            refresh()
        } catch {
            statusIsError = true
            statusMessage = "Could not delete key: \(error.localizedDescription)"
        }
    }
}
