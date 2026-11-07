import Foundation

@MainActor
public final class ExtensionPermissionApprovalCenter {
    public static let shared = ExtensionPermissionApprovalCenter()

    public var hasPresenter = false

    public private(set) var pendingRequest: ExtensionPermissionRequest?

    public static let pendingRequestDidChangeNotification =
        Notification.Name("ExtensionPermissionApprovalCenter.pendingRequestDidChange")

    private var continuation: CheckedContinuation<Bool, Never>?

    public init() {}

    public func ask(_ request: PermissionRequest) async -> Bool {
        guard hasPresenter, pendingRequest == nil else { return false }
        let pending = ExtensionPermissionRequest(request: request)
        pendingRequest = pending
        postChange()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func answer(id: UUID, approved: Bool) {
        guard let pending = pendingRequest, pending.id == id else { return }
        pendingRequest = nil
        postChange()
        continuation?.resume(returning: approved)
        continuation = nil
    }

    public func dismissPending() {
        guard let pending = pendingRequest else { return }
        answer(id: pending.id, approved: false)
    }

    private func postChange() {
        NotificationCenter.default.post(
            name: Self.pendingRequestDidChangeNotification, object: self)
    }
}

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
