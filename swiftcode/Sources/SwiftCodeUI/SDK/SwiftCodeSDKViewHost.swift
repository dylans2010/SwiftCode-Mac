import AppKit
import Foundation
import SwiftCodeSDK

// MARK: - SwiftCodeSDKViewHost
//
// Wave 16, Slice C: the `SDKViewHost` seam for the 12 SDK view
// windows, implemented in SwiftCode's own UI (not Legacy's).
//
// Legacy drove its own window managers (`DatabaseExplorerWindowManager`,
// …) and a toolbar-notification bridge (`ToolbarActionManager`,
// `com.swiftcode.toolbarToolActivated`); neither exists in SwiftCode and
// neither is re-ported. Instead each of the 12 view IDs is routed to
// the SwiftCode surface that actually hosts that job, or — where no such
// surface exists — fails honestly with `.serviceUnavailable` naming
// the exact reason. A window is never faked, and an empty placeholder
// is never opened and called the window.
//
// Per-window disposition (verified live against SwiftCode source; the
// full table with Legacy evidence is in
// `~/SwiftCode-Migration-Workspace/drafts/wave16-slice-c.md`):
//
//   Working (real SwiftCode surface):
//   - `deviceconnect.open`  → Device Hub, Devices section
//                             (`WorkspaceWindowController.presentDevices`)
//   - `simulator.view`      → Device Hub, Simulators section
//   - `uibuilder.open`      → Interface Builder editor, opened on the
//                             project's first .storyboard/.xib
//                             (`.storyboard`/`.xib` → `open(path:line:)`)
//   - `symbols.browse`      → Library panel, Symbols tab
//                             (`showLibrary` + `select(tab: .symbols)`)
//   - `preview.live`        → Preview canvas in the editor area
//                             (`setCanvasShown(true)`)
//   - `assist.main`         → Coding Assistant pane
//                             (`revealCodingAssistant()`; not one of
//                             the 12, but the same seam serves it)
//   - `dictionary.open`     → Coding Dictionary window (Wave 17,
//                             Slice C: generated per query through
//                             the host's configured text provider;
//                             Legacy shipped no term data to port)
//   - `db.ExploreView`      → SQLite Explorer window (Wave 17,
//                             Slice C: open a SQLite file, browse
//                             tables/rows, run SQL — over SwiftCode's
//                             existing `SQLiteDatabase`)
//   - `docs.search`         → Documentation Browser window (Wave 19,
//                             Slice A: the 57-topic offline cache,
//                             fetched live once from the public DocC
//                             endpoints and served offline; see
//                             `specs/ide/wave19-docs.md`)
//   - `deployConsole.view`  → Deployments console window (Wave 19,
//                             Slice F / gap closure: `DeploymentWindowManager`)
//   - `ci.VisualWF`         → CI dashboard window (Wave 19, Slice F /
//                             gap closure: `CIWindowManager`)
//   - `virtualization.view` → Virtualization console window (Wave 19,
//                             Slice F / gap closure:
//                             `VirtualizationWindowManager`)
//   - `sandbox.view`        → Sandboxed terminal window (Wave 19,
//                             Slice F / gap closure:
//                             `SandboxTerminalWindowManager`)
//   Honestly unavailable (no hostable surface in SwiftCode): none —
//   every built-in view ID currently routes to a surface.
//
// Every workspace-anchored surface needs the key workspace window;
// with none open, opens throw `.serviceUnavailable` ("No workspace
// window is open.") rather than presenting into the void.
//
// The host is testable: the surfaces behind it are the injectable
// `SDKViewSurfaceActions` protocol, so tests drive a recording fake
// instead of AppKit windows.
//
// NOTE (coordinator wiring): this file imports SwiftCodeSDK, so
// `swiftcode/Package.swift` must add `"SwiftCodeSDK"` to the `SwiftCodeUI` target
// dependencies (and to `SwiftCodeUITests` for the host tests). Until that
// one-line wiring lands, this target does not compile — see the slice
// spec draft for the exact diff.

/// The SwiftCode surfaces behind the SDK view host. One method per
/// hostable surface; each throws `.serviceUnavailable` when its
/// surface cannot be shown (no workspace window, no document).
/// Main-actor isolated: every method presents UI.
@MainActor
public protocol SDKViewSurfaceActions: AnyObject {
    /// Shows the Device Hub on its Devices section.
    func showDevices() async throws
    /// Shows the Device Hub on its Simulators section.
    func showSimulators() async throws
    /// Opens the Interface Builder editor on the active project's
    /// first .storyboard/.xib; `.serviceUnavailable` when the project
    /// has no Interface Builder document.
    func openInterfaceBuilder() async throws
    /// Shows the Library panel on its Symbols tab.
    func showSymbolLibrary() throws
    /// Shows the live-preview canvas in the editor area.
    func showLivePreview() throws
    /// Reveals the Coding Assistant pane.
    func showCodingAssistant() throws
    /// Shows the Coding Dictionary window (Wave 17, Slice C).
    func showCodingDictionary() throws
    /// Shows the SQLite Explorer window (Wave 17, Slice C).
    func showDatabaseExplorer() throws
    /// Shows the Documentation Browser window (Wave 19, Slice A).
    func showDocumentationBrowser() throws
    /// Shows the Deployments console window for the key workspace
    /// (Wave 19, Slice F / gap closure). `.serviceUnavailable` when no workspace
    /// window is open.
    func showDeployConsole() async throws
    /// Shows the CI dashboard window for the key workspace
    /// (Wave 19, Slice F / gap closure). `.serviceUnavailable` when no workspace
    /// window is open.
    func showCIDashboard() async throws
    /// Shows the virtualization console window (Wave 19, Slice F / gap closure).
    /// Needs no project.
    func showVirtualizationConsole() throws
    /// Shows the sandboxed terminal window for the key workspace
    /// (Wave 19, Slice F / gap closure). `.serviceUnavailable` when no workspace
    /// window is open.
    func showSandboxTerminal() async throws
}

/// The live surface actions: the key workspace window's own
/// controllers. No window is invented here — every method delegates
/// to the surface SwiftCode already shows from its own menus.
@MainActor
public final class WorkspaceSDKViewSurfaceActions: SDKViewSurfaceActions {
    public init() {}

    /// The key workspace window, or `.serviceUnavailable` when no
    /// project window is open.
    private func workspace() throws -> WorkspaceWindowController {
        guard let wc = (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? WorkspaceWindowController else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "No workspace window is open.",
                suggestion: "Open a project first, then try again."
            )
        }
        return wc
    }

    public func showDevices() async throws {
        let wc = try workspace()
        let hub = await wc.presentDevices()
        hub.show(.devices)
    }

    public func showSimulators() async throws {
        let wc = try workspace()
        let hub = await wc.presentDevices()
        hub.show(.simulators)
    }

    public func openInterfaceBuilder() async throws {
        let wc = try workspace()
        guard let url = firstInterfaceBuilderDocument(under: wc.workspaceFolder) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The Interface Builder is not available for this project.",
                suggestion: "This project has no .storyboard or .xib document to open."
            )
        }
        wc.open(path: url.path, line: nil)
    }

    public func showSymbolLibrary() throws {
        let wc = try workspace()
        let lib = wc.showLibrary(nil)
        lib.select(tab: .symbols)
    }

    public func showLivePreview() throws {
        let wc = try workspace()
        wc.setCanvasShown(true)
    }

    public func showCodingAssistant() throws {
        let wc = try workspace()
        wc.revealCodingAssistant()
    }

    /// Neither window needs a project — Legacy's dictionary,
    /// database explorer, and documentation browser are all
    /// standalone — so these three actions do NOT go through the
    /// workspace-window gate above. They open their own windows
    /// directly; the dictionary generates entries per query, the
    /// explorer asks for a file, and the browser serves its offline
    /// cache.
    public func showCodingDictionary() throws {
        CodingDictionaryWindowManager.shared.showWindow()
    }

    public func showDatabaseExplorer() throws {
        SQLiteExplorerWindowManager.shared.showWindow()
    }

    public func showDocumentationBrowser() throws {
        DocumentationBrowserWindowManager.shared.showWindow()
    }

    /// Deploy / CI / sandbox are workspace-anchored like Devices:
    /// the folder comes from the key workspace window, and with
    /// none open the open fails honestly. The window managers
    /// create their default service when none is passed (a live
    /// `DeploymentService` / `GitHubActionsService` over the
    /// default secret store). Virtualization needs no project.
    public func showDeployConsole() async throws {
        let wc = try workspace()
        DeploymentWindowManager.shared.showWindow(workspaceFolder: wc.workspaceFolder)
    }

    public func showCIDashboard() async throws {
        let wc = try workspace()
        CIWindowManager.shared.showWindow(workspaceFolder: wc.workspaceFolder)
    }

    public func showVirtualizationConsole() throws {
        VirtualizationWindowManager.shared.showWindow()
    }

    public func showSandboxTerminal() async throws {
        let wc = try workspace()
        SandboxTerminalWindowManager.shared.showWindow(workspaceFolder: wc.workspaceFolder)
    }

    /// The active project's first .storyboard/.xib, deterministically
    /// by path. Build outputs and dependency trees are not descended
    /// into; at most 64 candidates are collected. `nil` when the
    /// project has no Interface Builder document at all.
    private func firstInterfaceBuilderDocument(under root: URL) -> URL? {
        let skippedDirs: Set<String> = ["DerivedData", "build", ".build", "Pods", ".git"]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) { _, _ in true }
        var found: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if skippedDirs.contains(url.lastPathComponent) { enumerator?.skipDescendants() }
                continue
            }
            if url.pathExtension == "storyboard" || url.pathExtension == "xib" {
                found.append(url)
                if found.count >= 64 { break }
            }
        }
        return found.sorted { $0.path < $1.path }.first
    }
}

/// The host UI's side of SDK view opening: one method, dispatched by
/// view ID. Unavailable windows throw `.serviceUnavailable` with the
/// per-window reason (never a fake window); unknown IDs throw
/// `.serviceUnavailable` naming the missing registration.
public final class SwiftCodeSDKViewHost: SDKViewHost, @unchecked Sendable {
    /// The windows with no hostable surface in SwiftCode, with the exact
    /// reason each one cannot be opened. The single source of truth
    /// for the honestly-unavailable set (mirrored in the slice spec).
    /// Currently empty: every built-in view ID routes to a surface
    /// (docs.search landed in Wave 19 Slice A; deployConsole.view,
    /// ci.VisualWF, virtualization.view and sandbox.view in Slice F).
    public static let unavailableReasons: [String: String] = [:]

    private let actions: any SDKViewSurfaceActions

    public init(actions: any SDKViewSurfaceActions) {
        self.actions = actions
    }

    public func open(viewID: String) async throws {
        switch viewID {
        case "docs.search":
            try await actions.showDocumentationBrowser()
        case "deployConsole.view":
            try await actions.showDeployConsole()
        case "ci.VisualWF":
            try await actions.showCIDashboard()
        case "virtualization.view":
            try await actions.showVirtualizationConsole()
        case "sandbox.view":
            try await actions.showSandboxTerminal()
        case "db.ExploreView":
            try await actions.showDatabaseExplorer()
        case "dictionary.open":
            try await actions.showCodingDictionary()
        case "deviceconnect.open":
            try await actions.showDevices()
        case "simulator.view":
            try await actions.showSimulators()
        case "uibuilder.open":
            try await actions.openInterfaceBuilder()
        case "symbols.browse":
            try await actions.showSymbolLibrary()
        case "preview.live":
            try await actions.showLivePreview()
        case SDKAssistUIOpener.assistMainViewID:
            try await actions.showCodingAssistant()
        default:
            throw SDKError(
                code: .serviceUnavailable,
                message: "The view “\(viewID)” is not available.",
                suggestion: "No host surface is registered for this view."
            )
        }
    }

    /// The honest-unavailable error for `viewID`. Precondition: the
    /// ID is in `unavailableReasons`.
    public static func unavailableError(viewID: String) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "The view “\(viewID)” is not available in this release.",
            suggestion: unavailableReasons[viewID] ?? "No host surface exists for this view in SwiftCode."
        )
    }
}

/// The active-workspace provider for view openers that need a
/// project (CI / virtualization registration enforces the project
/// requirement through it). Returns the key workspace window's
/// project folder, or `nil` when no workspace window is open.
@MainActor
public struct SwiftCodeActiveWorkspaceProvider: SDKActiveWorkspaceProviding {
    public init() {}

    public func activeProjectRoot() async -> URL? {
        guard let wc = (NSApp.keyWindow ?? NSApp.mainWindow)?.windowController as? WorkspaceWindowController else {
            return nil
        }
        return wc.workspaceFolder
    }
}

// MARK: - Installer

/// Installs the SDK host seams at app startup (called once from
/// `AppDelegate.applicationDidFinishLaunching`):
///   - the view host + active-workspace provider (this file),
///   - the Assist backend attachment (`SDKAssistHostBackend` with
///     the host provider resolver),
///   - `SDKBootstrap` (registers the 12 built-in view openers + the
///     Assist view opener and scans the extension registry).
/// Idempotent: a second call is a no-op.
@MainActor
public enum SwiftCodeSDKInstaller {
    private static var installed = false

    public static func installIfNeeded() async {
        guard !installed else { return }
        installed = true
        SDKViewHostRegistry.shared.host = SwiftCodeSDKViewHost(actions: WorkspaceSDKViewSurfaceActions())
        SDKActiveWorkspaceRegistry.shared.provider = SwiftCodeActiveWorkspaceProvider()
        let backend = SDKAssistHostBackend.shared
        await backend.install(resolver: SwiftCodeSDKAssistResolver())
        await backend.install(toolRunner: SwiftCodeSDKToolRunner())
        await SDKAssistService.shared.backend = backend
        await SDKBootstrap.bootstrapIfNeeded()
    }
}
