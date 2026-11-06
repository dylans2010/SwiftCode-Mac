import Foundation
import SwiftUI
import SwiftCodeAssistant

// Alternative Gemini keys, adapted from Legacy's
// `SwiftCode/Views/Settings/AlternativeKeysView.swift` onto SwiftCode's
// `GeminiKeyRotationManager` (`SwiftCodeAssistant/GeminiKeyRotation.swift`,
// the port of Legacy's `AlternativeKeyManager`). Keys are stored in
// the secret store (never in plain text here) and shown only masked;
// import, removal, removal of all keys, and manual rotation all call
// the manager's real methods. There is no manual active-key picker
// because the manager owns the active key (import sets the first
// available key, removal advances it, rotation picks the next one).

/// Manage the alternative Gemini API keys used for rotation.
struct AlternativeKeysSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var manager: GeminiKeyRotationManager?
    @State private var keys: [AlternativeKeyMetadata] = []
    @State private var activeKeyId: UUID?
    @State private var importText = ""
    @State private var showingImport = false
    @State private var showingRemoveAllConfirm = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        let c = ShellColors(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Alternative Gemini Keys").font(ShellFonts.rowBold)
                Spacer()
                Button("Rotate Now") { rotate() }
                    .disabled(keys.isEmpty)
                Button("Import Keys") { showingImport = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(10)
            if let statusMessage {
                Text(verbatim: statusMessage)
                    .font(ShellFonts.small)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
            Text("Keys are stored in the secret store and shown masked. The active key is chosen by the rotation manager; rotation moves to the next healthy key when one is rate-limited or fails.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            Hairline(color: c.separator)
            if keys.isEmpty {
                ContentUnavailableView(
                    "No alternative keys",
                    systemImage: "key",
                    description: Text("Import one or more Gemini API keys to rotate between them when a key is rate-limited.")
                )
            } else {
                List {
                    ForEach(keys) { key in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: key.maskedValue)
                                    .font(.system(.body, design: .monospaced))
                                Text(verbatim: "\(key.state.rawValue) · \(key.successCount) succeeded · \(key.failureCount) failed\(key.lastUsed.map { " · last used \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")")
                                    .font(ShellFonts.small)
                                    .foregroundStyle(c.secondaryLabel)
                            }
                            Spacer()
                            if key.id == activeKeyId {
                                Text("Active")
                                    .font(ShellFonts.small)
                                    .foregroundStyle(c.accent)
                            }
                            Button("Remove", role: .destructive) { removeKey(key) }
                        }
                    }
                }
                .listStyle(.plain)
                HStack {
                    Button("Remove All Keys", role: .destructive) { showingRemoveAllConfirm = true }
                    Spacer()
                    Text(verbatim: "\(keys.count) key\(keys.count == 1 ? "" : "s")")
                        .font(ShellFonts.small)
                        .foregroundStyle(c.secondaryLabel)
                }
                .padding(10)
            }
        }
        .onAppear { loadManager() }
        .sheet(isPresented: $showingImport) {
            importSheet(colors: c)
        }
        .alert("Remove all alternative keys?", isPresented: $showingRemoveAllConfirm) {
            Button("Remove All", role: .destructive) { removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All alternative Gemini keys will be deleted from the secret store. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func importSheet(colors c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import Gemini Keys").font(ShellFonts.rowBold)
            Text("Paste one or more keys, separated by commas, newlines or semicolons. Duplicates are detected by hash and skipped; keys that fail validation are rejected.")
                .font(ShellFonts.small)
                .foregroundStyle(c.secondaryLabel)
            TextEditor(text: $importText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .border(c.fieldStroke)
            HStack {
                Spacer()
                Button("Cancel") { showingImport = false }
                Button("Import") {
                    importKeys()
                    showingImport = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func loadManager() {
        let store = CodingAssistantServices.shared.store
        let created = GeminiKeyRotationManager(store: store)
        manager = created
        Task { await refresh(created) }
    }

    private func refresh(_ manager: GeminiKeyRotationManager) async {
        keys = await manager.keys
        activeKeyId = await manager.activeKeyId
    }

    private func importKeys() {
        guard let manager else { return }
        let text = importText
        importText = ""
        Task {
            let result = await manager.importKeys(text)
            statusIsError = false
            if result.newKeysAdded == 0 {
                statusIsError = true
                statusMessage = "No keys added (\(result.totalDetected) detected, \(result.duplicatesRemoved) duplicates, \(result.invalidKeysRejected) invalid)."
            } else {
                statusMessage = "Added \(result.newKeysAdded) key\(result.newKeysAdded == 1 ? "" : "s") (\(result.duplicatesRemoved) duplicates, \(result.invalidKeysRejected) invalid)."
            }
            await refresh(manager)
        }
    }

    private func removeKey(_ key: AlternativeKeyMetadata) {
        guard let manager else { return }
        Task {
            await manager.removeKey(id: key.id)
            statusIsError = false
            statusMessage = "Removed key \(key.maskedValue)."
            await refresh(manager)
        }
    }

    private func removeAll() {
        guard let manager else { return }
        Task {
            await manager.removeAllKeys()
            statusIsError = false
            statusMessage = "Removed all alternative keys."
            await refresh(manager)
        }
    }

    private func rotate() {
        guard let manager else { return }
        Task {
            if let next = await manager.rotateNow() {
                statusIsError = false
                statusMessage = "Rotated to \(next.maskedValue)."
            } else {
                statusIsError = true
                statusMessage = "No healthy key to rotate to."
            }
            await refresh(manager)
        }
    }
}
