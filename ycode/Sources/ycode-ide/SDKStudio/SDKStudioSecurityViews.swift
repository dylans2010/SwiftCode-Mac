import Foundation
import SwiftUI
import YcodeExtensions
import YcodeSDK
import YcodeSDKStudio

// MARK: - Developer API keys
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioAPIKeysView.swift`.
// Lists developer keys (metadata only — the secret is shown exactly
// once at generation), generate with live/test environment + scopes,
// revoke with confirmation. The store is the Studio seam
// (`SDKStudioAPIKeyStore`); the default is the live Host adapter
// (`SDKHostAPIKeyStore`, Keychain-backed HMAC-SHA256 `sc_dev_live_` /
// `sc_dev_test_` secrets). A nil store shows the seam as unavailable
// instead of inventing key storage — the generate sheet is disabled and
// says so. An in-memory store is deliberately NOT provided: a key store
// that forgets keys on restart would silently break verification.

@MainActor
struct SDKStudioAPIKeysView: View {
    var keyStore: (any SDKStudioAPIKeyStore)?

    @State private var keys: [SDKStudioAPIKey] = []
    @State private var errorMessage: String?
    @State private var showingGenerateSheet = false
    @State private var confirmingRevoke: SDKStudioAPIKey?
    @State private var isLoading = false

    init(keyStore: (any SDKStudioAPIKeyStore)? = SDKHostAPIKeyStore()) {
        self.keyStore = keyStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Developer API Keys").font(.title2.bold())
                Spacer()
                Button("Refresh") { loadKeys() }
                Button("Generate Key") { showingGenerateSheet = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(keyStore == nil)
            }
            .padding(8)
            if keyStore == nil {
                Text("No developer API key store is connected. Key generation and revocation are disabled until a store is provided — Studio will not store keys anywhere else.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(8)
            }
            if isLoading {
                ProgressView("Loading keys…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if keys.isEmpty {
                SDKStudioEmptyState(title: "No API Keys", systemImage: "key",
                                     description: keyStore == nil
                                        ? "No key store is connected."
                                        : "Generate a key to authenticate SDK clients.")
            } else {
                List(keys) { key in
                    keyRow(key)
                }
                .listStyle(.plain)
            }
        }
        .task { loadKeys() }
        .sheet(isPresented: $showingGenerateSheet) {
            if let keyStore {
                SDKStudioGenerateKeySheet(keyStore: keyStore) { created in
                    keys.append(created)
                    showingGenerateSheet = false
                }
            }
        }
        .alert("Revoke API key?", isPresented: Binding(
            get: { confirmingRevoke != nil },
            set: { if !$0 { confirmingRevoke = nil } }
        ), presenting: confirmingRevoke) { target in
            Button("Revoke", role: .destructive) { revokeKey(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("This revokes “\(target.label)” (\(target.keyPrefix)…). Clients using it will fail verification immediately.")
        }
    }

    private func keyRow(_ key: SDKStudioAPIKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key.label).font(.headline)
                environmentChip(isLive: key.isLive)
                if key.isRevoked {
                    Text("revoked").font(.caption2).foregroundStyle(.red)
                } else if key.isExpired {
                    Text("expired").font(.caption2).foregroundStyle(.red)
                }
                Spacer()
                Button("Revoke") { confirmingRevoke = key }
                    .font(.caption)
                    .disabled(key.isRevoked || keyStore == nil)
            }
            Text("\(key.keyPrefix)…").font(.callout.monospaced())
            HStack(spacing: 6) {
                ForEach(Array(key.scopes).sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { scope in
                    Text(scope.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                ForEach(Array(key.entitlements).sorted(), id: \.self) { entitlement in
                    Text(entitlement)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
            Text("Created \(key.createdAt.formatted(date: .abbreviated, time: .shortened))\(key.lastUsedAt.map { " · Last used \($0.formatted(date: .abbreviated, time: .shortened))" } ?? " · Never used")\(key.expiresAt.map { " · Expires \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func environmentChip(isLive: Bool) -> some View {
        Text(isLive ? "live" : "test")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isLive ? Color.red : Color.blue).opacity(0.15), in: Capsule())
    }

    private func loadKeys() {
        guard let keyStore else { keys = []; return }
        isLoading = true
        Task {
            do {
                keys = try await keyStore.list()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func revokeKey(_ key: SDKStudioAPIKey) {
        guard let keyStore else { return }
        Task {
            do {
                try await keyStore.revoke(id: key.id)
                loadKeys()
            } catch {
                errorMessage = error.localizedDescription
            }
            confirmingRevoke = nil
        }
    }
}

@MainActor
private struct SDKStudioGenerateKeySheet: View {
    let keyStore: any SDKStudioAPIKeyStore
    let onCreated: (SDKStudioAPIKey) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var isLive = false
    @State private var selectedScopes: Set<SDKStudioAPIKeyScope> = [.appsCreate]
    @State private var secret: String?
    @State private var didCopy = false
    @State private var isCreating = false
    @State private var errorText: String?

    private let allScopes: [SDKStudioAPIKeyScope] = [.appsCreate, .appsPublish, .capabilitiesRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate API Key").font(.title2.bold())
            if let secret {
                Text("Copy this secret now — it is shown exactly once and never stored.")
                    .foregroundStyle(.red)
                Text(secret)
                    .font(.callout.monospaced())
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                Text(didCopy ? "Copied." : "")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Copy") { didCopy = true }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                TextField("Label", text: $label)
                    .textFieldStyle(.roundedBorder)
                Picker("Environment", selection: $isLive) {
                    Text("Test").tag(false)
                    Text("Live").tag(true)
                }
                .pickerStyle(.segmented)
                ForEach(allScopes, id: \.rawValue) { scope in
                    Toggle(scope.rawValue, isOn: Binding(
                        get: { selectedScopes.contains(scope) },
                        set: { newValue in
                            if newValue { selectedScopes.insert(scope) } else { selectedScopes.remove(scope) }
                        }
                    ))
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Generate") { generate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(label.isEmpty || selectedScopes.isEmpty || isCreating)
                }
            }
        }
        .padding()
        .frame(minWidth: 480)
    }

    private func generate() {
        isCreating = true
        Task {
            do {
                let created = try await keyStore.createKey(
                    label: label, isLive: isLive, scopes: selectedScopes, expiresAt: nil)
                secret = created.secret
                onCreated(created.key)
            } catch {
                errorText = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Security manager
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKSecurityManagerView.swift` —
// per-app `use.Security` values: list, add (with label + prompt text),
// delete one, delete all. Backed by the Studio security seam; the
// default is the live Host adapter (`SDKHostSecurityStore`, S-4) over
// the Host slice's `SDKSecurityService.listAllApps` enumeration
// (metadata only — values are never listed). A nil store shows the seam
// as unavailable instead of inventing storage — Studio will not keep
// secrets in UserDefaults or plain files.

@MainActor
struct SDKSecurityManagerView: View {
    var securityStore: (any SDKStudioSecurityStore)?

    @State private var apps: [SDKStudioSecurityApp] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddSheet = false
    @State private var selectedAppID: String?
    @State private var confirmingDeleteValue: (appID: String, valueID: String)?
    @State private var confirmingDeleteAll: String?

    init(securityStore: (any SDKStudioSecurityStore)? = SDKHostSecurityStore()) {
        self.securityStore = securityStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Security").font(.title2.bold())
                Spacer()
                Button("Reload") { loadApps() }
            }
            .padding(8)
            if securityStore == nil {
                Text("No security store is connected. Stored values cannot be listed, added, or deleted from Studio until one is provided — Studio will not keep secrets in UserDefaults or plain files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding(8)
            }
            if isLoading {
                ProgressView("Loading stored values…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.isEmpty {
                SDKStudioEmptyState(title: "No Stored Values", systemImage: "lock.shield",
                                     description: securityStore == nil
                                        ? "No security store is connected."
                                        : "No apps have stored security values yet.")
            } else {
                List(apps) { app in
                    appSection(app)
                }
                .listStyle(.plain)
            }
        }
        .task { loadApps() }
        .sheet(isPresented: $showingAddSheet) {
            if let securityStore, let appID = selectedAppID {
                SDKSecurityAddValueSheet(securityStore: securityStore, appID: appID) {
                    showingAddSheet = false
                    loadApps()
                }
            }
        }
        .alert("Delete value?", isPresented: Binding(
            get: { confirmingDeleteValue != nil },
            set: { if !$0 { confirmingDeleteValue = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let target = confirmingDeleteValue { deleteValue(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the stored value.")
        }
        .alert("Delete all values?", isPresented: Binding(
            get: { confirmingDeleteAll != nil },
            set: { if !$0 { confirmingDeleteAll = nil } }
        )) {
            Button("Delete All", role: .destructive) {
                if let appID = confirmingDeleteAll { deleteAll(appID) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every stored value for this app.")
        }
    }

    private func appSection(_ app: SDKStudioSecurityApp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(app.displayName).font(.headline)
                Text(app.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Add Value") {
                    selectedAppID = app.id
                    showingAddSheet = true
                }
                .font(.caption)
                .disabled(securityStore == nil)
                Button("Delete All") { confirmingDeleteAll = app.id }
                    .font(.caption)
                    .disabled(securityStore == nil)
            }
            ForEach(app.valueIDs, id: \.self) { valueID in
                HStack {
                    Text(valueID).font(.callout.monospaced())
                    Text("stored").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete") { confirmingDeleteValue = (app.id, valueID) }
                        .font(.caption)
                        .disabled(securityStore == nil)
                }
            }
            if app.valueIDs.isEmpty {
                Text("No stored values.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadApps() {
        guard let securityStore else { apps = []; return }
        isLoading = true
        Task {
            do {
                apps = try await securityStore.listApps()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func deleteValue(_ target: (appID: String, valueID: String)) {
        guard let securityStore else { return }
        Task {
            do {
                try await securityStore.deleteValue(valueID: target.valueID, forApp: target.appID)
                loadApps()
            } catch {
                errorMessage = error.localizedDescription
            }
            confirmingDeleteValue = nil
        }
    }

    private func deleteAll(_ appID: String) {
        guard let securityStore else { return }
        Task {
            do {
                try await securityStore.deleteAllValues(forApp: appID)
                loadApps()
            } catch {
                errorMessage = error.localizedDescription
            }
            confirmingDeleteAll = nil
        }
    }
}

@MainActor
private struct SDKSecurityAddValueSheet: View {
    let securityStore: any SDKStudioSecurityStore
    let appID: String
    let onStored: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueID = ""
    @State private var label = ""
    @State private var promptText = ""
    @State private var secret = ""
    @State private var errorText: String?
    @State private var isStoring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Security Value").font(.title2.bold())
            TextField("Value ID", text: $valueID)
                .textFieldStyle(.roundedBorder)
            TextField("Label (optional)", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Prompt text (optional)", text: $promptText)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret Value", text: $secret)
                .textFieldStyle(.roundedBorder)
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Store") { store() }
                    .buttonStyle(.borderedProminent)
                    .disabled(valueID.isEmpty || secret.isEmpty || isStoring)
            }
        }
        .padding()
        .frame(minWidth: 480)
    }

    private func store() {
        isStoring = true
        Task {
            do {
                try await securityStore.store(value: secret, valueID: valueID,
                                              label: label.isEmpty ? nil : label,
                                              promptText: promptText.isEmpty ? nil : promptText,
                                              forApp: appID)
                onStored()
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            isStoring = false
        }
    }
}

// MARK: - Secure-prompt entry
//
// Legacy: `SwiftCode/SDK/Studio/Views/EnterSecuritySDKView.swift` — the
// secure-prompt entry flow: the user types a secret value for one
// `use.Security` item, is warned when a value already exists (storing
// replaces it), and the value goes to the security store. Same seam as
// the security manager.

@MainActor
struct SDKEnterSecurityView: View {
    let appID: String
    let valueID: String
    let displayLabel: String
    let replacesExistingValue: Bool
    var securityStore: (any SDKStudioSecurityStore)?

    @State private var secret = ""
    @State private var storeError: String?
    @State private var isStoring = false
    @Environment(\.dismiss) private var dismiss

    init(appID: String, valueID: String, displayLabel: String, replacesExistingValue: Bool = false,
         securityStore: (any SDKStudioSecurityStore)? = SDKHostSecurityStore()) {
        self.appID = appID
        self.valueID = valueID
        self.displayLabel = displayLabel
        self.replacesExistingValue = replacesExistingValue
        self.securityStore = securityStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Security Value").font(.title2.bold())
            Text("The secure-prompt entry flow stores a secret value for “\(displayLabel)” in the host security store. The value itself is never displayed again.")
                .foregroundStyle(.secondary)
            if replacesExistingValue {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("A secret value is already stored for this item — storing replaces it.")
                }
                .font(.callout)
            }
            SecureField("Secret Value", text: $secret)
                .textFieldStyle(.roundedBorder)
            if let storeError {
                Text(storeError).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Store") { store() }
                    .buttonStyle(.borderedProminent)
                    .disabled(secret.isEmpty || isStoring || securityStore == nil)
            }
            if securityStore == nil {
                Text("No security store is connected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }

    private func store() {
        guard let securityStore else { return }
        isStoring = true
        Task {
            do {
                try await securityStore.store(value: secret, valueID: valueID, label: displayLabel,
                                              promptText: nil, forApp: appID)
                dismiss()
            } catch {
                storeError = error.localizedDescription
            }
            isStoring = false
        }
    }
}

// MARK: - Assist access form
//
// Legacy: `SwiftCode/SDK/Studio/Views/AssistAccessFormView.swift` — the
// Assist access application: extension + developer key, SDK variant,
// usage description, own-UI, third-party models, data-leaves-device,
// contact. Validation is the model's `validationErrors()`; submission
// (S-5) goes to the Host slice's `SDKAssistApplicationStore` — the API
// key secret is pasted into a `SecureField`, held in memory only for
// the submit call, verified against the Keychain-backed key store, and
// never persisted by the form. Approval stays a separate host action;
// the form never approves applications itself.

@MainActor
struct SDKAssistAccessFormView: View {
    @State private var extensionID = ""
    @State private var displayName = ""
    @State private var selectedKeyID: String?
    @State private var variant: SDKStudioAssistAccessApplication.Variant = .newApplication
    @State private var sdkVariant: SDKAssistSDKVariant = .assistSDKUI
    @State private var apiKeySecret = ""
    @State private var usageDescription = ""
    @State private var hasOwnUI = false
    @State private var ownUIDescription = ""
    @State private var usesThirdPartyModels = false
    @State private var thirdPartyModels = ""
    @State private var dataLeavesDevice = false
    @State private var dataDestination = ""
    @State private var contactEmail = ""
    @State private var fieldErrors: [String: String] = [:]
    @State private var submitted: SDKStudioAssistAccessApplication?
    @State private var submittedApplication: SDKAssistApplication?
    @State private var submitMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Assist Access").font(.title2.bold())
                Text("Apply for Assist access for your app. Required — your choices determine which SDK variant fits your app.")
                    .foregroundStyle(.secondary)
                SDKStudioGroupBox("Application") {
                    VStack(alignment: .leading, spacing: 8) {
                        field("Extension ID", error: fieldErrors["extensionID"]) {
                            TextField("com.example.my-app", text: $extensionID)
                        }
                        field("Display Name", error: fieldErrors["displayName"]) {
                            TextField("My App", text: $displayName)
                        }
                        Picker("Variant", selection: $variant) {
                            Text("New Application").tag(SDKStudioAssistAccessApplication.Variant.newApplication)
                            Text("Existing Application").tag(SDKStudioAssistAccessApplication.Variant.existingApplication)
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SDK variant").font(.headline)
                            Picker("SDK variant", selection: $sdkVariant) {
                                ForEach(SDKAssistSDKVariant.allCases, id: \.self) { option in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.displayLabel)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(option)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                        field("Developer API Key Secret", error: fieldErrors["apiKeySecret"]) {
                            SecureField("Paste the key secret (sc_dev_…)", text: $apiKeySecret)
                        }
                        Text("Paste the secret shown once when the key was generated. It is verified against the Keychain-backed key store on submit and never saved by this form.")
                            .font(.caption).foregroundStyle(.secondary)
                        field("Usage Description", error: fieldErrors["usageDescription"]) {
                            TextEditor(text: $usageDescription).frame(height: 80)
                        }
                    }
                }
                SDKStudioGroupBox("UI & Models") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Do you have your own UI for Assist responses?", isOn: $hasOwnUI)
                        if hasOwnUI {
                            field("Describe your UI", error: fieldErrors["ownUIDescription"]) {
                                TextEditor(text: $ownUIDescription).frame(height: 60)
                            }
                        }
                        Toggle("Do you use third-party models?", isOn: $usesThirdPartyModels)
                        if usesThirdPartyModels {
                            field("Third-party models", error: fieldErrors["thirdPartyModels"]) {
                                TextField("Model names…", text: $thirdPartyModels)
                            }
                        }
                    }
                }
                SDKStudioGroupBox("Data & Contact") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Does user data leave the device?", isOn: $dataLeavesDevice)
                        if dataLeavesDevice {
                            field("Data destination", error: fieldErrors["dataDestination"]) {
                                TextField("Where does user data go?", text: $dataDestination)
                            }
                        }
                        field("Contact Email", error: fieldErrors["contactEmail"]) {
                            TextField("you@example.com", text: $contactEmail)
                        }
                    }
                }
                HStack {
                    Button("Submit Application") { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)
                    Button("Reset") { resetForm() }
                }
                if let submitMessage {
                    Text(submitMessage).foregroundStyle(.secondary)
                }
                if let submitted, let submittedApplication {
                    SDKStudioGroupBox("Application Summary") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Application \(submittedApplication.id.uuidString) — \(submittedApplication.status.rawValue)")
                            Text("Extension: \(submitted.extensionID) — \(submitted.displayName)")
                            Text("Variant: \(submitted.variant.rawValue)")
                            Text("SDK variant: \(submitted.sdkVariant.displayLabel)")
                            Text("Own UI: \(submitted.hasOwnUI ? "yes" : "no")")
                            Text("Third-party models: \(submitted.usesThirdPartyModels ? "yes" : "no")")
                            Text("Data leaves device: \(submitted.dataLeavesDevice ? "yes" : "no")")
                            Text("Contact: \(submitted.contactEmail)")
                            Text("Submitted \(submittedApplication.submittedAt.formatted(date: .abbreviated, time: .shortened)). Approval is a separate host action — no entitlements are granted until it is approved.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding()
        }
    }

    private func field<Content: View>(_ label: String, error: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            content()
                .textFieldStyle(.roundedBorder)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func currentApplication() -> SDKStudioAssistAccessApplication {
        SDKStudioAssistAccessApplication(
            extensionID: extensionID, displayName: displayName, keyID: selectedKeyID, variant: variant,
            sdkVariant: sdkVariant,
            usageDescription: usageDescription, hasOwnUI: hasOwnUI,
            ownUIDescription: hasOwnUI ? ownUIDescription : nil,
            usesThirdPartyModels: usesThirdPartyModels,
            thirdPartyModels: usesThirdPartyModels ? thirdPartyModels : nil,
            dataLeavesDevice: dataLeavesDevice,
            dataDestination: dataLeavesDevice ? dataDestination : nil,
            contactEmail: contactEmail)
    }

    private func submit() {
        let application = currentApplication()
        var errors = application.validationErrors()
        if apiKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["apiKeySecret"] = "Paste the developer API key secret for this application."
        }
        fieldErrors = errors
        guard errors.isEmpty else {
            submitMessage = "Fix the highlighted fields before submitting."
            submitted = nil
            submittedApplication = nil
            return
        }
        isSubmitting = true
        submitMessage = nil
        Task {
            do {
                let decided = try await application.submit(apiKeySecret: apiKeySecret)
                submitted = application
                submittedApplication = decided
                submitMessage = "Application submitted and pending review."
            } catch {
                submitted = nil
                submittedApplication = nil
                submitMessage = "Submission failed: \((error as? SDKError)?.message ?? error.localizedDescription)"
            }
            // The secret is never retained past the submit call.
            apiKeySecret = ""
            isSubmitting = false
        }
    }

    private func resetForm() {
        extensionID = ""
        displayName = ""
        selectedKeyID = nil
        variant = .newApplication
        sdkVariant = .assistSDKUI
        apiKeySecret = ""
        usageDescription = ""
        hasOwnUI = false
        ownUIDescription = ""
        usesThirdPartyModels = false
        thirdPartyModels = ""
        dataLeavesDevice = false
        dataDestination = ""
        contactEmail = ""
        fieldErrors = [:]
        submitted = nil
        submittedApplication = nil
        submitMessage = nil
    }
}
