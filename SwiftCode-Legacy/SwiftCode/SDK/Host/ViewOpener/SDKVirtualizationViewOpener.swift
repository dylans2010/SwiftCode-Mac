import AppKit
import Foundation
import SwiftUI

@MainActor
public struct SDKVirtualizationViewOpener {
    nonisolated public static let capabilityID: SDKCapabilityID = .virtualizationView

    public static func open() throws {
        let project = try SDKActiveProjectResolver.resolve()
        VirtualizationWindowManager.shared.showWindow(for: project)
    }
}
