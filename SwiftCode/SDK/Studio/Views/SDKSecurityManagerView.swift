import Foundation
import Security
import SwiftUI

// MARK: - SDKSecurityManagerView
//
// Studio → Security (use.Security manager).
//
// Lists every Security ID (per-app namespace) that has stored sensitive
// values, and per Security ID the value IDs with METADATA ONLY (label,
// created date). Secret values are never listed, never displayed, and never
// pass through this view: there is deliberately no reveal button and no
// copy-secret button.
//
// HOST SURFACES (all real, no mocks):
// - `KeychainSDK.listValueIDs(securityID:)` — value metadata for one
//   namespace (value ID, optional label, created/modified dates; never the
//   secret bytes).
// - `KeychainSDK.deleteValue(securityID:valueID:)` — deletes one value
//   (idempotent).
// - `KeychainSDK.deleteAllValues(securityID:)` — deletes a whole namespace
//   (idempotent).
// - `SDKSensitiveValuePrompt.requestValue(securityID:appDisplayName:valueID:label:prompt:)`
//   — the narrow surface to the host secure-prompt coordinator (the same
//   coordinator the IPC layer uses). The coordinator presents the secure
//   prompt and stores the secret directly into the Keychain; Studio never
//   sees the value.
//
// Namespace enumeration (`enumerateSecurityIDs`) is a private helper here
// because `KeychainSDK` exposes per-namespace listing but no namespace
// enumeration. It is an attributes-only Keychain query (`kSecReturnData` is
// never set), filtered client-side to `KeychainSDK.servicePrefix`; when the
// sibling security store/broker lands namespace enumeration, this helper
// should defer to it.
//
// Errors are typed (`SDKError` message + suggestion) and shown inline, like
// `SDKStudioAPIKeysView`. Per the store's contract, no error from the
// security system ever carries secret material, so displaying errors
// verbatim is safe.
//
// Native macOS SwiftUI: Foundation + Security + SwiftUI only, no AppKit.

public struct SDKSecurityManagerView: View {
    public init() {}

    @State private var apps: [SecurityApp] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddSheet = false
    @State private var confirmingDeleteValue = false
    @State private var deleteValueTarget: DeleteValueTarget?
    @State private var confirmingDeleteAll = false
    @State private var deleteAllTarget: DeleteAllTarget?

    /// One Security ID (per-app namespace) with its stored value metadata.
    private struct SecurityApp {
        let securityID: String
        let values: [KeychainSDK.ValueMetadata]
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                Text("Sensitive values are stored per app in the macOS Keychain and are never shown here — only which values exist and when they were added. Adding a value opens the host secure prompt, which collects the secret directly into the Keychain; Studio never sees it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
                if isLoading {
                    ProgressView("Loading stored values…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if apps.isEmpty {
                    emptyState
                } else {
                    appList
                }
            }
            .navigationTitle("Security")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Value") { showingAddSheet = true }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { @MainActor in await loadApps() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddValueSheet(apps: apps) {
                    Task { @MainActor in await loadApps() }
                }
            }
            .alert("Delete value?", isPresented: $confirmingDeleteValue, presenting: deleteValueTarget) { target in
                Button("Delete Value", role: .destructive) {
                    Task { @MainActor in await deleteValue(target) }
                }
            } message: { target in
                Text("This permanently deletes the value “\(target.displayLabel)” (\(target.valueID)) for “\(target.securityID)” from the Keychain. This cannot be undone — the app will no longer be able to use this value until it is stored again.")
            }
            .alert("Delete all values?", isPresented: $confirmingDeleteAll, presenting: deleteAllTarget) { target in
                Button("Delete All Values", role: .destructive) {
                    Task { @MainActor in await deleteAllValues(target) }
                }
            } message: { target in
                Text("This permanently deletes all \(target.valueCount) stored value\(target.valueCount == 1 ? "" : "s") for “\(target.securityID)” from the Keychain. This cannot be undone — the app will no longer be able to use any of these values until they are stored again.")
            }
            .task {
                await loadApps()
            }
        }
    }

    // MARK: - List

    private var appList: some View {
        List {
            ForEach(apps, id: \.securityID) { app in
                Section {
                    ForEach(app.values, id: \.valueID) { entry in
                        valueRow(app: app, entry: entry)
                    }
                } header: {
                    appHeader(app)
                }
            }
        }
    }

    private func appHeader(_ app: SecurityApp) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.securityID)
                    .font(.headline.monospaced())
            }
            Spacer()
            Text("\(app.values.count) value\(app.values.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete All", role: .destructive) {
                deleteAllTarget = DeleteAllTarget(
                    securityID: app.securityID,
                    valueCount: app.values.count
                )
                confirmingDeleteAll = true
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }

    private func valueRow(app: SecurityApp, entry: KeychainSDK.ValueMetadata) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Metadata only. The secret bytes are never returned by
                // `listValueIDs` and there is no path in this view to read
                // them — no reveal, no copy.
                if let label = entry.label, !label.isEmpty {
                    Text(label)
                        .font(.body)
                    Text(entry.valueID)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(entry.valueID)
                        .font(.body.monospaced())
                }
                Text("Added \(entry.created.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete", role: .destructive) {
                let displayLabel: String = {
                    if let label = entry.label, !label.isEmpty { return label }
                    return entry.valueID
                }()
                deleteValueTarget = DeleteValueTarget(
                    securityID: app.securityID,
                    valueID: entry.valueID,
                    displayLabel: displayLabel
                )
                confirmingDeleteValue = true
            }
            .buttonStyle(.link)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Stored Values", systemImage: "lock.shield")
        } description: {
            Text("No app has stored a sensitive value yet. Add one to store a secret for an app through the host secure prompt — the value goes straight into the Keychain and is never shown here.")
        } actions: {
            Button("Add Value") { showingAddSheet = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Errors

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.callout)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(10)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Store access

    @MainActor
    private func loadApps() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let ids = try enumerateSecurityIDs()
            var loaded: [SecurityApp] = []
            for id in ids {
                // Metadata only — `listValueIDs` never returns secret bytes.
                let values = try KeychainSDK.listValueIDs(securityID: id)
                guard !values.isEmpty else { continue }
                loaded.append(SecurityApp(securityID: id, values: values))
            }
            apps = loaded
        } catch {
            presentError(error)
        }
    }

    @MainActor
    private func deleteValue(_ target: DeleteValueTarget) async {
        errorMessage = nil
        do {
            try KeychainSDK.deleteValue(securityID: target.securityID, valueID: target.valueID)
            await loadApps()
        } catch {
            presentError(error)
        }
    }

    @MainActor
    private func deleteAllValues(_ target: DeleteAllTarget) async {
        errorMessage = nil
        do {
            try KeychainSDK.deleteAllValues(securityID: target.securityID)
            await loadApps()
        } catch {
            presentError(error)
        }
    }

    /// Returns every Security ID with at least one stored value. Temporary
    /// enumeration path (see the file header): an attributes-only Keychain
    /// query filtered client-side to `KeychainSDK.servicePrefix`. Secret
    /// data is never requested.
    private func enumerateSecurityIDs() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not list stored security values.",
                suggestion: "The macOS Keychain could not be reached. Check that the Keychain is unlocked and try again.",
                diagnostics: ["operation": "enumerate-security-ids", "osstatus": String(status)]
            )
        }
        guard let items = result as? [[String: Any]] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not list stored security values.",
                diagnostics: ["operation": "enumerate-security-ids", "reason": "unexpected-result-shape"]
            )
        }
        let prefix = KeychainSDK.servicePrefix + "."
        let ids = Set(
            items.compactMap { $0[kSecAttrService as String] as? String }
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .filter { !$0.isEmpty }
        )
        return ids.sorted()
    }

    /// Renders the user-safe `SDKError` message (plus suggestion) inline.
    /// Per the security store's contract, no error from the security system
    /// ever carries secret material, so this is safe to display verbatim.
    @MainActor
    private func presentError(_ error: Error) {
        if let sdkError = error as? SDKError {
            errorMessage = [sdkError.message, sdkError.suggestion]
                .compactMap { $0 }
                .joined(separator: " ")
        } else {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete targets

    private struct DeleteValueTarget: Identifiable {
        let securityID: String
        let valueID: String
        let displayLabel: String

        var id: String { "\(securityID)/\(valueID)" }
    }

    private struct DeleteAllTarget: Identifiable {
        let securityID: String
        let valueCount: Int

        var id: String { securityID }
    }

    // MARK: - AddValueSheet

    /// Collects the Security ID, value ID, label, and explanatory prompt,
    /// then hands off to `SDKSensitiveValuePrompt.requestValue` — the same
    /// host secure-prompt coordinator the IPC layer uses. The sheet never
    /// sees the secret: the coordinator presents the secure prompt and
    /// stores the value directly into the Keychain under the app's
    /// namespace.
    private struct AddValueSheet: View {
        let apps: [SecurityApp]
        var onStored: () -> Void

        @Environment(\.dismiss) private var dismiss

        @State private var selectedSecurityID: String?
        @State private var newSecurityID = ""
        @State private var valueID = ""
        @State private var label = ""
        @State private var promptText = ""
        @State private var isStoring = false
        @State private var errorText: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Sensitive Value")
                    .font(.title2)
                    .bold()
                Text("The value is collected by the host secure prompt and stored in the Keychain under the app's namespace. Studio never sees it, and it is never displayed here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("App (Security ID)")
                        .font(.headline)
                    Picker("App", selection: $selectedSecurityID) {
                        Text("New Security ID…").tag(nil as String?)
                        ForEach(apps, id: \.securityID) { app in
                            Text(app.securityID).tag(app.securityID as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 340, alignment: .leading)
                    if selectedSecurityID == nil {
                        TextField("e.g. openai.api-key", text: $newSecurityID)
                            .textFieldStyle(.roundedBorder)
                        Text("Reverse-DNS style, at least two dot-separated segments.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Value ID")
                        .font(.headline)
                    TextField("e.g. api-key", text: $valueID)
                        .textFieldStyle(.roundedBorder)
                    Text("The storage identity within the app's namespace — the same ID the app uses to request this value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(.headline)
                    TextField("e.g. OpenAI API key", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt (optional)")
                        .font(.headline)
                    TextField("What should the secure prompt tell the user?", text: $promptText)
                        .textFieldStyle(.roundedBorder)
                    Text("Shown in the secure prompt to explain which secret to enter. Leave empty for the default prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    sheetErrorBanner(errorText)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isStoring)
                    Button("Store Value") {
                        Task { @MainActor in await store() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isStoring)
                }
            }
            .frame(minWidth: 480)
            .padding(20)
            .liquidGlass(style: .sheet, cornerRadius: 12)
        }

        private func sheetErrorBanner(_ text: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(text)
                    .font(.callout)
            }
            .padding(10)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }

        @MainActor
        private func store() async {
            errorText = nil
            let securityID: String
            if let selectedSecurityID {
                securityID = selectedSecurityID
            } else {
                securityID = newSecurityID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !securityID.isEmpty else {
                    errorText = "Enter a Security ID for the new app namespace."
                    return
                }
            }
            let trimmedValueID = valueID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValueID.isEmpty else {
                errorText = "Enter a value ID."
                return
            }
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLabel.isEmpty else {
                errorText = "Enter a label for this value."
                return
            }
            isStoring = true
            defer { isStoring = false }
            do {
                // The narrow host surface: the same secure-prompt coordinator
                // the IPC layer uses. The secret is collected by the prompt
                // and stored directly — it never passes through this sheet.
                try await SDKSensitiveValuePrompt.requestValue(
                    securityID: securityID,
                    appDisplayName: securityID,
                    valueID: trimmedValueID,
                    label: trimmedLabel,
                    prompt: promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                onStored()
                dismiss()
            } catch is CancellationError {
                // The user dismissed the secure prompt: not an error, the
                // sheet just closes with nothing stored.
                dismiss()
            } catch {
                presentError(error)
            }
        }

        @MainActor
        private func presentError(_ error: Error) {
            if let sdkError = error as? SDKError {
                errorText = [sdkError.message, sdkError.suggestion]
                    .compactMap { $0 }
                    .joined(separator: " ")
            } else {
                errorText = error.localizedDescription
            }
        }
    }
}
