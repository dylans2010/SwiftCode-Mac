import Foundation
import SwiftUI

// MARK: - EnterSecuritySDKView
//
// The native macOS popup where the USER types a secret so an app
// (extension) can have it stored in its private Keychain namespace without
// ever seeing the plaintext (the `security.addValue` flow, spec
// `SDK/Documentation/Security-Keychain.md` §"The secure-prompt entry flow").
//
// PRESENTED BY THE HOST ONLY — never by extension code. Extensions run
// out-of-process and cannot reach this type; `SDKSensitiveValuePrompt` is
// the only presenter, and it is called from host-owned code (the IPC layer
// or Studio).
//
// WHAT THE USER SEES: which app is asking (display name + Security ID —
// the exact Keychain namespace the secret lands in) and which value (label
// + value ID, e.g. "MyApp wants to store 'openai-key'"), an optional
// context line, a SecureField, and Cancel / Store.
//
// SECRECY CONTRACT:
// - The typed text lives in `@State private var secret` and NEVER leaves
//   this view except into `KeychainSDK.addValue(...)` — the host's own
//   same-process Keychain write, called from the Store action.
//   `onStored` / `onCancelled` carry no payload: no binding, no value, and
//   no text escapes to extension-facing code.
// - Typed `SDKError`s shown inline never contain secret bytes:
//   `KeychainSDK`'s diagnostics carry only operation / osstatus / reason by
//   construction, and this view never interpolates the secret into text.
// - The field is cleared before `onStored` / `onCancelled` fire, so no
//   plaintext lingers in view state after the prompt resolves.

public struct EnterSecuritySDKView: View {

    // MARK: - Request (host-supplied)

    /// The app's Security ID: the Keychain namespace the secret is stored
    /// under (`com.swiftcode.sdk.security.<securityID>`). Shown verbatim so
    /// the user sees exactly where the secret lands. Assigned by the host
    /// from the verified extension identity — never from extension input.
    private let securityID: String
    /// Host-known display name of the requesting app.
    private let appDisplayName: String
    /// The Security Value ID being stored (e.g. "openai-key").
    private let valueID: String
    /// Human label stored on the Keychain item; shown as the field label.
    private let label: String?
    /// Optional extension-supplied context line, rendered as inert text.
    private let prompt: String?

    // MARK: - Outcome (payload-free)

    /// Fired after the Keychain write succeeded. Carries no payload.
    private let onStored: () -> Void
    /// Fired when the user cancels. Carries no payload.
    private let onCancelled: () -> Void

    // MARK: - State (view-local)

    @State private var secret = ""
    @State private var storeError: SDKError?
    @State private var isStoring = false
    @State private var replacesExistingValue = false
    @FocusState private var secretFieldFocused: Bool

    public init(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String?,
        onStored: @escaping () -> Void,
        onCancelled: @escaping () -> Void
    ) {
        self.securityID = securityID
        self.appDisplayName = appDisplayName
        self.valueID = valueID
        self.label = label
        self.prompt = prompt
        self.onStored = onStored
        self.onCancelled = onCancelled
    }

    /// Blank means empty or whitespace-only. A whitespace-only "secret" is
    /// rejected rather than stored: it is virtually always a paste slip,
    /// and a stored stray newline would fail authentication later.
    /// Anything else is stored EXACTLY as typed — never trimmed.
    private var isBlankInput: Bool {
        secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fieldLabel: String {
        label ?? valueID
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            requestingApp

            if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            secretField

            if replacesExistingValue {
                Label(
                    "A value is already stored for “\(valueID)” — storing replaces it.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let storeError {
                inlineError(storeError)
            }

            Spacer(minLength: 4)

            Divider()

            buttons
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            secretFieldFocused = true
            replacesExistingValue =
                (try? KeychainSDK.hasValue(securityID: securityID, valueID: valueID)) ?? false
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Store a Secret")
                    .font(.title2)
                    .bold()
                Text("\(appDisplayName) wants to store “\(valueID)”")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requestingApp: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Requesting app")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(appDisplayName)
                .font(.headline)
            HStack(spacing: 6) {
                Text("Security ID:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(securityID)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
            }
            Text("The extension will never see this value — SwiftCode stores it in the Mac’s Keychain under this app’s private namespace, and only uses it for the operations you approve.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fieldLabel)
                .font(.headline)
            SecureField("Type or paste the secret", text: $secret)
                .focused($secretFieldFocused)
                .disabled(isStoring)
                .accessibilityLabel(Text(fieldLabel))
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button("Cancel") { cancel() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                .disabled(isStoring)

            Spacer()

            Button("Store") { store() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isBlankInput || isStoring)
        }
    }

    private func inlineError(_ error: SDKError) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(error.message)
                    .font(.callout)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
            }
            .foregroundStyle(.red)
            if let suggestion = error.suggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(error.correlationId)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func store() {
        storeError = nil
        guard !isBlankInput else {
            storeError = SDKError(
                code: .invalidArgument,
                message: "Enter a value before storing it.",
                suggestion: "Type or paste the secret into the field above, then press Store."
            )
            return
        }
        guard !isStoring else { return }
        isStoring = true
        defer { isStoring = false }

        do {
            // The ONLY place the typed secret goes: straight into the
            // Keychain under the app's namespaced partition. No callback,
            // binding, or log ever receives it.
            try KeychainSDK.addValue(
                securityID: securityID,
                valueID: valueID,
                data: Data(secret.utf8),
                label: label
            )
            // Drop the plaintext before reporting success: the @State
            // buffer is released with the view, and nothing but the
            // Keychain write ever held it.
            secret = ""
            onStored()
        } catch let sdkError as SDKError {
            // Typed SDK errors are safe to show verbatim: KeychainSDK's
            // diagnostics carry only operation / osstatus / reason — never
            // secret material.
            storeError = sdkError
        } catch {
            storeError = SDKError(
                code: .serviceUnavailable,
                message: "Could not store the secret.",
                suggestion: "The macOS Keychain could not be reached. Check that the Keychain is unlocked and try again."
            )
        }
    }

    private func cancel() {
        // Drop any typed plaintext before reporting the cancellation.
        secret = ""
        onCancelled()
    }
}
