import AppKit
import Foundation
import SwiftUI

// MARK: - SDKSensitiveValuePrompt
//
// Host-side coordinator for the `security.addValue` flow: the piece the IPC
// layer (and Studio) calls when an app needs the USER to type a secret into
// its private Keychain namespace (spec
// `SDK/Documentation/Security-Keychain.md` §"The secure-prompt entry flow").
//
// The extension never sees the plaintext — not in the request, not in the
// response, not in any callback. `EnterSecuritySDKView` keeps the typed
// text in view-local `@State` and writes it straight to the Keychain via
// `KeychainSDK.addValue(...)`; this coordinator only learns the OUTCOME
// (stored / cancelled) through parameterless callbacks.
//
// TRUST BOUNDARIES (mirrors `SDKIPCDispatcher`'s security model):
// - `securityID` and `appDisplayName` MUST come from host-known state — the
//   installed-extension registry plus the verified session identity — never
//   from the extension's IPC payload. `KeychainSDK` derives the vault
//   partition (`com.swiftcode.sdk.security.<securityID>`) from the
//   securityID alone, so an extension-influenced value here would be a
//   cross-namespace write primitive.
// - `valueID`, `label`, and `prompt` are the extension's request
//   parameters. `KeychainSDK` validates their shape at write time and the
//   view surfaces those typed errors inline; they are rendered as inert
//   display text, never trusted for identity.
// - The identity block shows the host-known display name and Security ID.
//   The validated package digest is not shown because this contract does
//   not carry it; a future revision may add it when the IPC route supplies
//   the verified digest.
//
// BEHAVIOR:
// - Presents `EnterSecuritySDKView` in its own titled window on the main
//   actor, following the `SDKStudioWindowManager` pattern
//   (`NSHostingController`, `center`, `makeKeyAndOrderFront`,
//   `NSApp.activate`). One window per request, so concurrent prompts from
//   different apps do not block each other.
// - Resolves when the user presses Store (the view already wrote the
//   Keychain item — nothing left to do), presses Cancel, or closes the
//   window. Cancel / dismissal surfaces as `CancellationError`, so callers
//   can distinguish "the user dismissed the prompt" (not an error) from a
//   real failure — the same distinction `SDKSecurityManagerView` relies on.
// - Waits for the user with NO timeout of its own: fetching a secret is
//   user-paced. Callers that budget requests (e.g. the dispatcher's
//   per-request watchdog, when the `security.*` routes land) own timeout
//   policy. Task cancellation does not dismiss the window: if the caller's
//   task is cancelled while the prompt is visible, the window stays until
//   the user acts, and the abandoned continuation simply is never observed.
//
// AUDIT: when the user stores the value, this coordinator records
// `securityValueAdded` (identifiers only: Security ID + value ID — never
// the secret, never the label) BEFORE resolving, so the event is on the
// record before any caller observes success. It is recorded here — rather
// than by each caller — because this coordinator is the single choke point
// for every prompt-driven store (the `security.addValue` IPC route AND the
// Studio Security manager), and the manager path has no extension identity
// to attribute. The acting-app identity recorded is the Security ID
// itself: the host-assigned vault namespace derived from the verified
// extension identity. IPC routes must NOT record a second
// `securityValueAdded` for the same store.

@MainActor
public final class SDKSensitiveValuePrompt: NSObject, NSWindowDelegate {

    // MARK: - Public surface

    /// Asks the user to type a secret for (`securityID`, `valueID`) and
    /// stores it straight into the Keychain under the app's namespaced
    /// vault partition, then returns. The typed value never passes through
    /// this call — the prompt writes it directly via `KeychainSDK`.
    ///
    /// - Parameters:
    ///   - securityID: The app's Security ID (host-assigned from the
    ///     verified extension identity). The Keychain partition
    ///     `com.swiftcode.sdk.security.<securityID>`.
    ///   - appDisplayName: Host-known display name of the requesting app,
    ///     shown in the prompt's identity block.
    ///   - valueID: The Security Value ID being stored (e.g. "openai-key").
    ///   - label: Human label stored on the Keychain item and shown as the
    ///     field label.
    ///   - prompt: Optional context line shown in the prompt.
    ///
    /// - Throws: `SDKError` (`.invalidArgument` for an empty request field;
    ///   `.serviceUnavailable` and friends from the Keychain write,
    ///   surfaced inline in the prompt so the user can retry) or
    ///   `CancellationError` when the user cancels or dismisses the prompt
    ///   — in which case nothing was stored.
    public static func requestValue(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String?
    ) async throws {
        try await shared.requestValue(
            securityID: securityID,
            appDisplayName: appDisplayName,
            valueID: valueID,
            label: label,
            prompt: prompt
        )
    }

    // MARK: - Plumbing

    /// Single shared instance: owns in-flight prompt windows and serves as
    /// their `NSWindowDelegate`. The public surface stays static so the
    /// narrow call shape is identical for the IPC layer and Studio.
    private static let shared = SDKSensitiveValuePrompt()

    /// One entry per visible prompt window. The entry is removed the moment
    /// its prompt resolves, which is also the exactly-once guard for the
    /// suspended caller's continuation.
    private var inFlight: [NSWindow: InFlightPrompt] = [:]

    private override init() {
        super.init()
    }

    private func requestValue(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String?
    ) async throws {
        guard !securityID.isEmpty, !appDisplayName.isEmpty, !valueID.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid secret-store request.",
                suggestion: "The requesting app, its Security ID, and the value ID must all be supplied by the host.",
                diagnostics: ["reason": "empty-request-field"]
            )
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            presentPrompt(
                securityID: securityID,
                appDisplayName: appDisplayName,
                valueID: valueID,
                label: label,
                prompt: prompt,
                continuation: continuation
            )
        }
    }

    // MARK: - Presentation

    /// Presents the secure prompt in its own titled window on the main
    /// actor. One window per request: concurrent prompts from different apps
    /// do not block each other.
    private func presentPrompt(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Store Secret — \(appDisplayName)"
        window.delegate = self
        // Lifetime is managed through `inFlight`, not AppKit's release.
        window.isReleasedWhenClosed = false

        // The callbacks are plain `() -> Void`: the secret never crosses
        // them. They hop to the main actor to resolve, keeping this file
        // warning-free under complete strict concurrency. The weak captures
        // also break the retain cycle (self -> inFlight -> window ->
        // hosting controller -> view -> closure -> self).
        let view = EnterSecuritySDKView(
            securityID: securityID,
            appDisplayName: appDisplayName,
            valueID: valueID,
            label: label,
            prompt: prompt,
            onStored: { [weak self, weak window] in
                guard let window else { return }
                Task { @MainActor in
                    await self?.resolve(window: window, result: .success(()))
                }
            },
            onCancelled: { [weak self, weak window] in
                guard let window else { return }
                Task { @MainActor in
                    await self?.resolve(window: window, result: .failure(CancellationError()))
                }
            }
        )
        window.contentViewController = NSHostingController(rootView: view)
        inFlight[window] = InFlightPrompt(
            continuation: continuation,
            securityID: securityID,
            valueID: valueID
        )

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Resolution

    /// Resolves one prompt exactly once, then closes its window. Removing
    /// the `inFlight` entry first makes any second resolution path (e.g. the
    /// title-bar close arriving after a button press) a no-op.
    private func resolve(window: NSWindow, result: Result<Void, Error>) async {
        guard let prompt = inFlight.removeValue(forKey: window) else { return }
        window.delegate = nil
        switch result {
        case .success:
            // The store is the significant trust action: audit it
            // (identifiers only) BEFORE resuming, so the event is on the
            // record before any caller observes success.
            await SDKAuditLog.shared.record(
                type: .securityValueAdded,
                extensionID: prompt.securityID,
                capability: .securityAddValue,
                detail: "\(prompt.securityID) / \(prompt.valueID)",
                correlationId: SDKError.newCorrelationId()
            )
            prompt.continuation.resume()
        case .failure(let error):
            prompt.continuation.resume(throwing: error)
        }
        window.close()
    }

    // MARK: - NSWindowDelegate

    /// The title-bar close button is a cancellation: the user dismissed the
    /// prompt without storing anything.
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              inFlight[window] != nil else { return }
        Task { @MainActor in
            await self.resolve(window: window, result: .failure(CancellationError()))
        }
    }
}

// MARK: - InFlightPrompt

/// Bookkeeping for one visible secure prompt: the suspended caller's
/// continuation plus the identifiers needed to resolve it (audit detail).
/// Never carries secret material.
private struct InFlightPrompt {
    let continuation: CheckedContinuation<Void, Error>
    let securityID: String
    let valueID: String
}
