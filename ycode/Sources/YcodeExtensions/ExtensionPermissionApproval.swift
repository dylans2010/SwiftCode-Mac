import Foundation

/// Capability approval UI — the Wave 11 remainder.
///
/// `PermissionManager.request` is deny-by-default: already granted
/// returns true immediately, and with no `promptHandler` installed a
/// request is denied outright (a headless call is a denial, not a
/// queue). Until this file, nothing in the destination ever installed
/// a `promptHandler` — Legacy never did either — so every
/// host-initiated capability request (`ExtensionManager.swift`,
/// `permissions.request`) was denied without the user ever seeing
/// it. This center is the missing piece: the handler the manager
/// installs at startup, plus the UI that answers it.
///
/// The center never grants anything itself. `ask` suspends the
/// requesting task on a continuation until a person answers; the
/// answer flows back through `PermissionManager.request`, which
/// grants only on an explicit approval. With no UI presented (a
/// headless run, a test), `ask` still waits for an answer — callers
/// that cannot present UI must not install the handler, and the
/// manager's default remains denial.
///
/// Presentation is deliberately separate: this file owns the queue,
/// the AppKit panel observes the queue (see
/// `ExtensionsPanelViewController`, exact patch in the gap-closure
/// report) and a SwiftUI host renders `ExtensionPermissionApprovalView`
/// for one pending request. Either presenter answers through
/// `answer(id:approved:)`; the other sees the request disappear.
/// Presenters set `hasPresenter` when they start observing; without
/// one, `ask` denies immediately, preserving the headless default.

@MainActor
public final class ExtensionPermissionApprovalCenter {
    public static let shared = ExtensionPermissionApprovalCenter()

    /// Set by a presenter (AppKit panel, SwiftUI host) when it
    /// starts observing. Until then the center has nobody to ask,
    /// and requests are denied rather than left hanging.
    public var hasPresenter = false

    /// The request currently awaiting an answer, if any. Changes
    /// are announced through the notification below, so both
    /// SwiftUI and AppKit presenters can observe it without a
    /// Combine dependency (this target builds on Linux, where
    /// Combine does not exist).
    public private(set) var pendingRequest: ExtensionPermissionRequest?

    public static let pendingRequestDidChangeNotification =
        Notification.Name("ExtensionPermissionApprovalCenter.pendingRequestDidChange")

    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {}

    /// Suspends until a person answers the request. Returns true
    /// only on an explicit approval. A second request while one is
    /// pending is denied immediately rather than queued behind an
    /// unseen prompt — one question at a time, no silent backlog.
    /// With no presenter installed, denies immediately.
    public func ask(_ request: PermissionRequest) async -> Bool {
        guard hasPresenter, pendingRequest == nil else { return false }
        let pending = ExtensionPermissionRequest(request: request)
        pendingRequest = pending
        postChange()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    /// Answers the pending request (or ignores the call when the id
    /// does not match the pending one). The waiting task resumes
    /// with the answer; `PermissionManager` grants on approval.
    public func answer(id: UUID, approved: Bool) {
        guard let pending = pendingRequest, pending.id == id else { return }
        pendingRequest = nil
        postChange()
        continuation?.resume(returning: approved)
        continuation = nil
    }

    /// Dismisses the pending request as a denial (panel closed
    /// without answering, window closed, app quitting).
    public func dismissPending() {
        guard let pending = pendingRequest else { return }
        answer(id: pending.id, approved: false)
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: Self.pendingRequestDidChangeNotification, object: self)
    }
}

/// One capability question, as the UI shows it.
public struct ExtensionPermissionRequest: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var extensionId: String
    public var capability: ExtensionCapability
    public var reason: String

    public init(id: UUID = UUID(), request: PermissionRequest) {
        self.id = id
        self.extensionId = request.extensionId
        self.capability = request.capability
        self.reason = request.reason
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The approval sheet for one pending request, mirroring the SDK
/// broker's `SDKApprovalView`: the extension, the capability with
/// its risk level, and the reason the extension gave. Allow and
/// Deny are the only exits — there is no "always allow", and an
/// ungrantable capability (`assist.invoke`) is shown as not
/// available rather than offered. The presenting host owns
/// observation (it watches
/// `pendingRequestDidChangeNotification` and shows this view while
/// a request is pending); this view only renders and answers.
/// AppKit hosts use an `NSAlert` sheet instead (same center, same
/// answer path).
public struct ExtensionPermissionApprovalView: View {
    var center: ExtensionPermissionApprovalCenter
    var request: ExtensionPermissionRequest

    public init(center: ExtensionPermissionApprovalCenter = .shared,
                request: ExtensionPermissionRequest) {
        self.center = center
        self.request = request
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extension Capability Request")
                .font(.headline)
            Text("“\(request.extensionId)” wants to use this capability:")
            HStack {
                Text(request.capability.displayName)
                    .font(.body.weight(.semibold))
                Text("· \(request.capability.riskLevel) risk")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if !request.reason.isEmpty {
                Text(request.reason)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if !request.capability.isGrantable {
                Text("This capability is not available in this release and cannot be granted.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Deny") {
                    center.answer(id: request.id, approved: false)
                }
                .keyboardShortcut(.cancelAction)
                Button("Allow") {
                    center.answer(id: request.id, approved: true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!request.capability.isGrantable)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }
}
#endif
