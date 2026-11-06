import Foundation

// MARK: - SDKVirtualizationViewOpener
//
// Ported from Legacy `SwiftCode/SDK/Host/ViewOpener/SDKVirtualizationViewOpener.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Opens the virtualization console (`virtualization.view`) for the
// active project. Requires a project — `.projectNotOpen` otherwise.
// The console itself is owned by the host UI behind the `SDKViewHost`
// seam; this file owns only the view ID, the project requirement, and
// the registration.

public enum SDKVirtualizationViewOpener {
    public static let viewID = "virtualization.view"

    public static func register() async {
        await SDKViewOpener.shared.register(viewID: viewID) {
            _ = try await SDKActiveProjectResolver.activeProjectRoot()
            try await SDKViewHostRegistry.shared.open(viewID: viewID)
        }
    }
}
