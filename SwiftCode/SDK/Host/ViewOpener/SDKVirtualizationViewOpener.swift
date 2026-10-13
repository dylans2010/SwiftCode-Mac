import AppKit
import Foundation
import SwiftUI

// MARK: - SDKVirtualizationViewOpener
//
// View opener for capability `virtualization.view` ("Virtualization console").
//
// NOTE (2026-10-12 correction): this opener previously served `sandbox.view`.
// `sandbox.view` now opens SwiftCode's real Terminal view; the Virtualization
// console moved to its own `virtualization.view` ID.
//
// ## Which surface opens
// `VirtualizationWindowManager.shared.showWindow(for:)` — the app's
// supported entry point for the full virtualization console
// (SwiftCode/Views/Developer/Virtualization/AppKit/VirtualizationWindowController.swift,
// `public func showWindow(for project: Project)`). It opens/reuses the
// "Virtualization Console" `NSWindow` (1100×750) whose content is the
// `VirtualizationSplitViewController` (sidebar + workspace). This is the
// exact call the app's own "Virtualization" menu command
// (AppCommands.swift) and the `SCVirtualizationView` trampoline make.
//
// ## Project resolution
// Via `SDKActiveProjectResolver`: `ProjectSessionStore.shared.activeProject`,
// falling back to `projects.first` — identical to the menu command's
// resolution. When neither exists the opener throws the existing typed
// project-missing error, `SDKErrorCode.projectNotOpen` (`PROJECT_NOT_OPEN`);
// it never silently does nothing.
//
// ## Verification status
// Statically verified only — no Swift toolchain in this environment.
// Needs `xcodebuild` on Dylan's Mac: target membership of the new file and
// a live open of the Virtualization Console through the capability.

@MainActor
public struct SDKVirtualizationViewOpener {
    /// Capability this opener serves: `virtualization.view`.
    nonisolated public static let capabilityID: SDKCapabilityID = .virtualizationView

    /// Opens the Virtualization Console window for the active project.
    /// - Throws: `SDKError` with code `.projectNotOpen` when no project is
    ///   open. Never a silent no-op.
    public static func open() throws {
        let project = try SDKActiveProjectResolver.resolve()
        VirtualizationWindowManager.shared.showWindow(for: project)
    }
}
