import Foundation

// MARK: - SDKSensitiveValuePrompt
//
// Ported from Legacy `SwiftCode/SDK/Host/Security/SDKSensitiveValuePrompt.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The host's secure secret-entry prompt for `security.addValue`. The
// extension never supplies the secret — the USER types it into a
// host-owned window, and the value flows straight to the Keychain
// vault. The coordinator learns only the outcome (a value was stored,
// or the user cancelled).
//
// Contract: `requestValue(securityID:appDisplayName:valueID:label:prompt:)`
// presents one window per request (deduplicated by in-flight map),
// resolves exactly once, audits `securityValueAdded` BEFORE resolving
// (identifiers only), Cancel/close throws `CancellationError`, no
// timeout, and task cancellation does not dismiss the window.
//
// The SwiftUI entry view (`SDKSecureValueEntryView`) is written here
// from that contract: Legacy's `EnterSecuritySDKView` lives in the
// Legacy app, outside this slice, and is deliberately never read.
// On platforms without AppKit/SwiftUI the prompt is unavailable and
// throws `.serviceUnavailable` — reported honestly, never faked.

#if os(macOS) && canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// The host's secure secret-entry coordinator.
@MainActor
public final class SDKSensitiveValuePrompt {
    public static let shared = SDKSensitiveValuePrompt()

    private var inFlight: [String: [CheckedContinuation<Data, Error>]] = [:]
    private var windows: [String: NSWindow] = [:]

    private init() {}

    /// Presents the secure entry window and returns the typed secret.
    /// Throws `CancellationError` when the user cancels or closes the
    /// window. Concurrent requests for the same security/value pair
    /// share one window and one outcome.
    public func requestValue(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String? = nil
    ) async throws -> Data {
        let key = "\(securityID)/\(valueID)"
        let alreadyOpen = inFlight[key] != nil
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            inFlight[key, default: []].append(continuation)
            guard !alreadyOpen else { return }
            let view = SDKSecureValueEntryView(
                appDisplayName: appDisplayName,
                valueID: valueID,
                label: label,
                prompt: prompt,
                onSubmit: { [weak self] value in
                    Task { @MainActor in
                        await self?.resolve(key: key, with: .success(Data(value.utf8)), securityID: securityID, valueID: valueID)
                    }
                },
                onCancel: { [weak self] in
                    Task { @MainActor in
                        await self?.resolve(key: key, with: .failure(CancellationError()))
                    }
                }
            )
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Store a Secret"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 260))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = WindowCloseHandler { [weak self] in
                Task { @MainActor in
                    await self?.resolve(key: key, with: .failure(CancellationError()))
                }
            }
            windows[key] = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Resolves every waiter for the request exactly once: the
    /// continuations are removed from the map first, the window is
    /// closed, and — on success — the audit event is recorded BEFORE
    /// any continuation resumes, so the audit trail never misses a
    /// stored value.
    private func resolve(key: String, with result: Result<Data, Error>, securityID: String? = nil, valueID: String? = nil) async {
        guard let continuations = inFlight.removeValue(forKey: key) else { return }
        windows.removeValue(forKey: key)?.close()
        switch result {
        case .success(let data):
            await SDKAuditLog.shared.record(
                .securityValueAdded,
                detail: "security \(securityID ?? "") value \(valueID ?? "")"
            )
            for continuation in continuations { continuation.resume(returning: data) }
        case .failure(let error):
            for continuation in continuations { continuation.resume(throwing: error) }
        }
    }
}

/// Forwards window-close to the prompt coordinator (Cancel).
private final class WindowCloseHandler: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - SDKSecureValueEntryView

/// Minimal secure secret-entry view, written from the documented
/// contract. The user types the secret into a `SecureField`; the value
/// leaves this view only through `onSubmit`, straight to the Keychain
/// vault. The coordinator learns only the outcome.
public struct SDKSecureValueEntryView: View {
    private let appDisplayName: String
    private let valueID: String
    private let label: String?
    private let prompt: String?
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void

    @State private var value = ""

    public init(
        appDisplayName: String,
        valueID: String,
        label: String? = nil,
        prompt: String? = nil,
        onSubmit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.appDisplayName = appDisplayName
        self.valueID = valueID
        self.label = label
        self.prompt = prompt
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appDisplayName)
                .font(.headline)
            Text(prompt ?? "Enter the secret to store for “\(label ?? valueID)”."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            SecureField("Secret", text: $value)
                .textFieldStyle(.roundedBorder)
            Text("The secret is stored in the Keychain and is never shown to the extension.")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Store Secret") { onSubmit(value) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(value.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

#else

/// No AppKit/SwiftUI host UI on this platform: the secure prompt is
/// unavailable. `security.addValue` reports `.serviceUnavailable`
/// honestly rather than accepting a secret through any other channel.
@MainActor
public final class SDKSensitiveValuePrompt {
    public static let shared = SDKSensitiveValuePrompt()

    private init() {}

    public func requestValue(
        securityID: String,
        appDisplayName: String,
        valueID: String,
        label: String?,
        prompt: String? = nil
    ) async throws -> Data {
        throw SDKError(
            code: .serviceUnavailable,
            message: "The secure secret prompt is not available on this platform.",
            suggestion: "Store the secret on macOS, where the host prompt is available."
        )
    }
}

#endif
