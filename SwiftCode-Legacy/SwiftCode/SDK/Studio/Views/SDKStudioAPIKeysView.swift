import Foundation
import SwiftUI

// MARK: - SDKStudioAPIKeysView
//
// Studio → Settings → Developer API Keys (spec §8.2.1).
//
// Lists the host's developer API keys (metadata only — secrets are never
// stored, so they are never listed), generates new keys through
// `SDKAPIKeyStore.createKey`, and revokes keys through
// `SDKAPIKeyStore.revoke(id:)` with a confirmation step. Revoked keys stay
// listed as revoked: the list is an audit trail.
//
// SECURITY CONTRACT (mirrors `SDKAPIKeyStore`):
// - The one-time secret is displayed EXACTLY ONCE in the generation sheet.
//   It is never logged, never persisted, never embedded in an error, and is
//   cleared from memory (`secret = nil`) when the user presses Done or the
//   sheet is otherwise dismissed.
// - Only key prefixes are shown (`sc_dev_live…` / `sc_dev_test…`), never a
//   secret or any part of one.
// - SwiftUI + Foundation only: no AppKit import. The Copy button writes via
//   `/usr/bin/pbcopy` through `Foundation.Process`.

public struct SDKStudioAPIKeysView: View {
    public init() {}

    @State private var keys: [SDKAPIKey] = []
    @State private var errorMessage: String?
    @State private var showingGenerateSheet = false
    @State private var confirmingRevoke = false
    @State private var revokeTarget: RevokeTarget?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                Text("Developer API keys authenticate apps and capability requests against the SwiftCode platform. Only key metadata is stored — each secret is shown once at creation and never again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
                if keys.isEmpty {
                    emptyState
                } else {
                    keyList
                }
            }
            .navigationTitle("Developer API Keys")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Generate Key") { showingGenerateSheet = true }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { @MainActor in await loadKeys() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
            .sheet(isPresented: $showingGenerateSheet) {
                GenerateKeySheet(onCreated: {
                    Task { @MainActor in await loadKeys() }
                })
            }
            .alert("Revoke API key?", isPresented: $confirmingRevoke, presenting: revokeTarget) { target in
                Button("Revoke Key", role: .destructive) {
                    Task { @MainActor in await revokeKey(id: target.id) }
                }
            } message: { target in
                Text("Revoking \"\(target.label)\" takes effect immediately — apps and sessions using this key will be denied from that moment on. This cannot be undone. Generate a new key if access is still needed.")
            }
            .task {
                await loadKeys()
            }
        }
    }

    // MARK: - List

    private var keyList: some View {
        List(keys, id: \.id) { key in
            keyRow(key)
        }
    }

    private func keyRow(_ key: SDKAPIKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(key.label)
                    .font(.headline)
                Spacer()
                if key.isRevoked {
                    revokedBadge
                } else {
                    Button("Revoke", role: .destructive) {
                        revokeTarget = RevokeTarget(id: key.id, label: key.label)
                        confirmingRevoke = true
                    }
                    .buttonStyle(.link)
                }
            }
            HStack(spacing: 8) {
                Text("\(key.keyPrefix)…")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                environmentChip(isLive: key.keyPrefix == SDKAPIKeyCodec.livePrefix)
            }
            HStack(spacing: 6) {
                ForEach(key.scopes.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { scope in
                    scopeChip(scope.rawValue)
                }
            }
            if !key.entitlements.isEmpty {
                HStack(spacing: 6) {
                    Text("Entitlements:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(key.entitlements.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { entitlement in
                        entitlementChip(entitlement.rawValue)
                    }
                }
            }
            Text("Created \(key.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastUsedAt = key.lastUsedAt {
                Text("Last used \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let expiresAt = key.expiresAt {
                Text(key.isExpired ? "Expired \(expiresAt.formatted(date: .abbreviated, time: .shortened))" : "Expires \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(key.isExpired ? .red : .secondary)
            }
            if let revokedAt = key.revokedAt {
                Text("Revoked \(revokedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(key.isRevoked ? 0.55 : 1.0)
    }

    private var revokedBadge: some View {
        Text("Revoked")
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
    }

    private func environmentChip(isLive: Bool) -> some View {
        Text(isLive ? "Live" : "Test")
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isLive ? Color.red.opacity(0.15) : Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(isLive ? .red : .blue)
    }

    private func scopeChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    /// Granted Assist entitlements (`com.SwiftCode.developer-AI-*`) — only
    /// ever added through the Assist access approval flow.
    private func entitlementChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(.purple)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No API Keys", systemImage: "key.fill")
        } description: {
            Text("Generate a developer API key to authenticate app creation, publishing, and privileged capability requests against the SwiftCode platform.")
        } actions: {
            Button("Generate Key") { showingGenerateSheet = true }
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
    private func loadKeys() async {
        keys = await SDKAPIKeyStore.shared.list()
    }

    @MainActor
    private func revokeKey(id: UUID) async {
        errorMessage = nil
        do {
            try await SDKAPIKeyStore.shared.revoke(id: id)
            keys = await SDKAPIKeyStore.shared.list()
        } catch {
            presentError(error)
        }
    }

    /// Renders the user-safe `SDKError` message (plus suggestion) inline.
    /// Per the store's contract, no error from the key system ever carries
    /// secret material, so this is safe to display verbatim.
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

    // MARK: - RevokeTarget

    private struct RevokeTarget: Identifiable {
        let id: UUID
        let label: String
    }

    // MARK: - GenerateKeySheet

    /// Key generation sheet. Two phases: the form, then — after a successful
    /// `createKey` — the one-time secret reveal. The secret `String` is held
    /// only in `@State` and is set to `nil` on Done or on any dismissal, so
    /// it cannot outlive the sheet.
    private struct GenerateKeySheet: View {
        var onCreated: () -> Void

        @Environment(\.dismiss) private var dismiss

        @State private var label = ""
        @State private var isLive = false
        @State private var selectedScopes: Set<SDKAPIKeyScope> = [.appsCreate]
        @State private var secret: String?
        @State private var didCopy = false
        @State private var isCreating = false
        @State private var errorText: String?

        private static let scopeOptions: [(scope: SDKAPIKeyScope, description: String)] = [
            (.appsCreate, "Create and configure apps targeting the SwiftCode platform."),
            (.appsPublish, "Publish, export, and release apps targeting the SwiftCode platform."),
            (.capabilitiesRequest, "Request privileged capabilities such as network access, custom builds, credential usage, and platform publishing."),
        ]

        var body: some View {
            Group {
                if let secret {
                    revealView(secret: secret)
                } else {
                    formView
                }
            }
            .frame(minWidth: 480)
            .padding(20)
            .liquidGlass(style: .sheet, cornerRadius: 12)
            .interactiveDismissDisabled(secret != nil)
            .onDisappear {
                // Belt-and-braces: the one-time secret must not survive the sheet.
                secret = nil
                didCopy = false
            }
        }

        // MARK: Form

        private var canGenerate: Bool {
            !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !selectedScopes.isEmpty
                && !isCreating
        }

        private var formView: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Generate API Key")
                    .font(.title2)
                    .bold()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label")
                        .font(.headline)
                    TextField("e.g. Release builds", text: $label)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Environment")
                        .font(.headline)
                    Picker("Environment", selection: $isLive) {
                        Text("Live").tag(true)
                        Text("Test").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    Text(isLive
                         ? "Live keys authenticate real platform actions."
                         : "Test keys are for development and experimentation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scopes")
                        .font(.headline)
                    ForEach(Self.scopeOptions, id: \.scope) { option in
                        Toggle(isOn: scopeBinding(for: option.scope)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.scope.rawValue)
                                    .font(.body.monospaced())
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                if let errorText {
                    sheetErrorBanner(errorText)
                }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Generate") {
                        Task { @MainActor in await generate() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGenerate)
                }
            }
        }

        private func scopeBinding(for scope: SDKAPIKeyScope) -> Binding<Bool> {
            Binding(
                get: { selectedScopes.contains(scope) },
                set: { isOn in
                    if isOn {
                        selectedScopes.insert(scope)
                    } else {
                        selectedScopes.remove(scope)
                    }
                }
            )
        }

        @MainActor
        private func generate() async {
            errorText = nil
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorText = "Enter a label for this key."
                return
            }
            guard !selectedScopes.isEmpty else {
                errorText = "Select at least one scope."
                return
            }
            isCreating = true
            defer { isCreating = false }
            do {
                // The secret is returned exactly once; it is never logged,
                // persisted, or embedded in an error by the store.
                let result = try await SDKAPIKeyStore.shared.createKey(
                    label: trimmed,
                    scopes: selectedScopes,
                    isLive: isLive
                )
                secret = result.secret
                onCreated()
            } catch {
                presentError(error)
            }
        }

        // MARK: One-time secret reveal

        private func revealView(secret: String) -> some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("API Key Created")
                    .font(.title2)
                    .bold()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This is the only time the secret is shown.")
                            .bold()
                        Text("Copy it now and store it somewhere safe. It cannot be recovered — if it is lost, revoke this key and generate a new one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                ScrollView {
                    Text(secret)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                if let errorText {
                    sheetErrorBanner(errorText)
                }
                HStack {
                    Button(didCopy ? "Copied" : "Copy") {
                        copySecretToClipboard(secret)
                    }
                    .disabled(didCopy)
                    Spacer()
                    Button("Done") {
                        // This was the secret's one and only display: clear it
                        // from memory before dismissing.
                        self.secret = nil
                        didCopy = false
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }

        /// Foundation-only clipboard write (no AppKit import): pipes the
        /// secret to `/usr/bin/pbcopy`. The secret is never logged.
        private func copySecretToClipboard(_ value: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy", isDirectory: false)
            let stdin = Pipe()
            process.standardInput = stdin
            do {
                try process.run()
                if let data = value.data(using: .utf8) {
                    try stdin.fileHandleForWriting.write(contentsOf: data)
                }
                try stdin.fileHandleForWriting.close()
                process.waitUntilExit()
                didCopy = process.terminationStatus == 0
            } catch {
                didCopy = false
                errorText = "Could not copy to the clipboard (\(error.localizedDescription)). Select the key text and press ⌘C instead."
            }
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
