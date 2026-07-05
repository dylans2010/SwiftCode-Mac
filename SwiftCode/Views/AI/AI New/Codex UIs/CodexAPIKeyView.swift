import SwiftUI

struct CodexAPIKeyView: View {
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var validationMessage = ""

    private var hasStoredKey: Bool {
        !(KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("OpenAI API Key", systemImage: "key.fill")
                        .font(.headline)
                    Text("Your key is stored securely in Keychain and is never rendered back on screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(hasStoredKey ? "Stored Securely" : "Not Configured", systemImage: hasStoredKey ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(hasStoredKey ? Color.green.opacity(0.14) : Color.orange.opacity(0.14))
                    .clipShape(Capsule())
            }

            SecureField(hasStoredKey ? "Enter a new API key to replace the current one" : "Enter OpenAI API key", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Save Key") {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                    } else {
                        KeychainService.shared.set(trimmed, forKey: KeychainService.codexUserAPIKey)
                    }
                    CodexManager.shared.refreshUsageMode()
                    validationMessage = trimmed.isEmpty ? "Stored key removed. App-managed restricted usage will be used when available." : "New key stored securely in Keychain."
                    apiKey = ""
                }
                .buttonStyle(.borderedProminent)

                Button("Validate") {
                    Task {
                        isValidating = true
                        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isValid = await CodexManager.shared.validateUserAPIKey(trimmed)
                        validationMessage = isValid ? "Key validated successfully." : "Key validation failed. Check that the key is active and has Codex access."
                        isValidating = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }

            if !validationMessage.isEmpty {
                Label(validationMessage, systemImage: validationMessage.contains("failed") ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(validationMessage.contains("failed") ? .red : .green)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
