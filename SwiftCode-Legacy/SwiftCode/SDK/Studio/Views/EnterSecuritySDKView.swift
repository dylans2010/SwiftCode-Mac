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
// WHAT THE USER SEES: which app is asking (display name) and the user-facing
// Label (if provided; never exposing Value ID or Security ID), an optional
// context line, a SecureField, and Cancel / Store.
//
// SECRECY CONTRACT & STRICT IDENTIFIER BOUNDARY:
// - Displays ONLY the human-facing Label (or "Secret Value" fallback).
// - Strictly prohibits displaying Value ID or Security ID anywhere in the
//   visible UI, metadata rows, tooltips, accessibility labels, or inline messages.
// - The typed text lives in `@State private var secret` and NEVER leaves
//   this view except into `KeychainSDK.addValue(...)` — the host's own
//   same-process Keychain write, called from the Store action.
//   `onStored` / `onCancelled` carry no payload: no binding, no value, and
//   no text escapes to extension-facing code.
// - The field is cleared before `onStored` / `onCancelled` fire, so no
//   plaintext lingers in view state after the prompt resolves.

public struct EnterSecuritySDKView: View {

    // MARK: - Request (host-supplied)

    /// The app's Security ID (used internally for Keychain partitioning; never displayed).
    private let securityID: String
    /// Host-known display name of the requesting app.
    private let appDisplayName: String
    /// The Security Value ID being stored (used internally for Keychain key; never displayed).
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

    /// Visible label for the sensitive value. Never falls back to valueID.
    private var displayLabel: String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return "Secret Value"
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            requestingApp

            if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            secretField

            if replacesExistingValue {
                Label(
                    label != nil ? "A value is already stored for “\(displayLabel)” — storing replaces it." : "A secret value is already stored for this item — storing replaces it.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let storeError {
                inlineError(storeError)
            }

            Spacer(minLength: 8)

            Divider()

            buttons
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 480, alignment: .top)
        .onAppear {
            secretFieldFocused = true
            replacesExistingValue =
                (try? KeychainSDK.hasValue(securityID: securityID, valueID: valueID)) ?? false
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Store a Secret")
                    .font(.title2)
                    .bold()
                Text(label != nil ? "\(appDisplayName) wants to store “\(displayLabel)”" : "\(appDisplayName) wants to store a secret")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requestingApp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Requesting app")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(appDisplayName)
                .font(.headline)
            Text("The extension will never see this value — SwiftCode stores it in the Mac’s Keychain under this app’s private namespace, and only uses it for the operations you approve.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .liquidGlass(style: .standard, cornerRadius: 12)
    }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayLabel)
                .font(.headline)
            SecureField("Type or paste the secret", text: $secret)
                .focused($secretFieldFocused)
                .disabled(isStoring)
                .accessibilityLabel(Text(displayLabel))
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
            try KeychainSDK.addValue(
                securityID: securityID,
                valueID: valueID,
                data: Data(secret.utf8),
                label: label
            )
            secret = ""
            onStored()
        } catch let sdkError as SDKError {
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
        secret = ""
        onCancelled()
    }
}
