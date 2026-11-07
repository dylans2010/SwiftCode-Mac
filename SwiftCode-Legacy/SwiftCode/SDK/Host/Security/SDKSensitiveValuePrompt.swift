import AppKit
import Foundation
import SwiftUI

@MainActor
public final class SDKSensitiveValuePrompt: NSObject, NSWindowDelegate {

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

    private static let shared = SDKSensitiveValuePrompt()

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
        window.isReleasedWhenClosed = false

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

    private func resolve(window: NSWindow, result: Result<Void, Error>) async {
        guard let prompt = inFlight.removeValue(forKey: window) else { return }
        window.delegate = nil
        switch result {
        case .success:
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

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              inFlight[window] != nil else { return }
        Task { @MainActor in
            await self.resolve(window: window, result: .failure(CancellationError()))
        }
    }
}

private struct InFlightPrompt {
    let continuation: CheckedContinuation<Void, Error>
    let securityID: String
    let valueID: String
}
