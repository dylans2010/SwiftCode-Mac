import Foundation
import SwiftUI
import SwiftCodeAssistant
import SwiftCodeIDECore

// Alternative Gemini keys, adapted from Legacy's
// `SwiftCode/Views/Settings/AlternativeKeysView.swift` onto SwiftCode's
// `GeminiKeyRotationManager` (`SwiftCodeAssistant/GeminiKeyRotation.swift`,
// the port of Legacy's `AlternativeKeyManager`). Keys are stored in
// the secret store (never in plain text here) and shown only masked;
// import, removal, removal of all keys, and manual rotation all call
// the manager's real methods. There is no manual active-key picker
// because the manager owns the active key (import sets the first
// available key, removal advances it, rotation picks the next one).
//
// Migration (Views/UI worklist, Legacy PARTIAL): ready/in-cooldown status
// counts, a Reset Cooldowns action (Legacy `resetHealth`, already present
// on `GeminiKeyRotationManager`), and drag-to-reorder rotation priority
// (Legacy `reorderKeys(from:to:)`; the destination manager takes an
// ordered id list via `reorderKeys(_:)`, so the view translates the
// IndexSet move into ids).

/// Manage the alternative Gemini API keys used for rotation.
struct AlternativeKeysSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var manager: GeminiKeyRotationManager?
    @State private var keys: [AlternativeKeyMetadata] = []
    @State private var activeKeyId: UUID?
    @State private var importText = ""
    @State private var showingImport = false
    @State private var showingRemoveAllConfirm = false
    @State private var isReordering = false
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
                Button("Reset Cooldowns") { resetCooldowns() }
                    .disabled(keys.isEmpty || !keys.contains { $0.isCurrentlyRateLimited || $0.state == .failed })
                Button(isReordering ? "Done" : "Reorder") { isReordering.toggle() }
                    .disabled(keys.count < 2)
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
            if !keys.isEmpty {
                statusCountsRow(colors: c)
            }
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
                    .onMove(perform: moveKeys)
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(isReordering ? .active : .inactive))
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

    /// Ready / in-cooldown counts (Legacy's status pill: `keys.filter {
    /// $0.isAvailableForUse }.count` ready, `keys.filter {
    /// $0.isCurrentlyRateLimited }.count` in cooldown).
    private func statusCountsRow(colors c: ShellColors) -> some View {
        let readyCount = keys.filter { $0.isAvailableForUse }.count
        let cooldownCount = keys.filter { $0.isCurrentlyRateLimited }.count
        return HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text(verbatim: "\(keys.count) key\(keys.count == 1 ? "" : "s") saved")
                .font(ShellFonts.small)
                .foregroundStyle(c.label)
            Text(verbatim: "·").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
            Text(verbatim: "\(readyCount) ready")
                .font(ShellFonts.small)
                .foregroundStyle(readyCount > 0 ? .green : c.secondaryLabel)
            if cooldownCount > 0 {
                Text(verbatim: "·").font(ShellFonts.small).foregroundStyle(c.secondaryLabel)
                Text(verbatim: "\(cooldownCount) in cooldown")
                    .font(ShellFonts.small)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(c.fieldFill, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Clears every cooldown (Legacy `resetHealth`, already on the manager:
    /// rate-limited / failed keys return to `.ready` with no
    /// `rateLimitedUntil`; disabled / invalid keys are left alone).
    private func resetCooldowns() {
        guard let manager else { return }
        Task {
            await manager.resetHealth()
            statusIsError = false
            statusMessage = "All key cooldowns reset."
            await refresh(manager)
        }
    }

    /// Drag-to-reorder: translates the List move into the manager's
    /// ordered-id reorder (Legacy `reorderKeys(from:to:)`).
    private func moveKeys(from source: IndexSet, to destination: Int) {
        guard let manager else { return }
        var reordered = keys
        reordered.move(fromOffsets: source, toOffset: destination)
        let orderedIDs = reordered.map { $0.id }
        keys = reordered
        Task {
            await manager.reorderKeys(orderedIDs)
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
