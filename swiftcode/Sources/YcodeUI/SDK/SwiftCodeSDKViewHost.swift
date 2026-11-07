import AppKit
import Foundation
import SwiftCodeSDK

@MainActor
public protocol SDKViewSurfaceActions: AnyObject {
    func showDevices() async throws
    func showSimulators() async throws
    func openInterfaceBuilder() async throws
    func showSymbolLibrary() throws
    func showLivePreview() throws
    func showCodingAssistant() throws
    func showCodingDictionary() throws
    func showDatabaseExplorer() throws
    func showDocumentationBrowser() throws
    func showDeployConsole() async throws
    func showCIDashboard() async throws
    func showVirtualizationConsole() throws
    func showSandboxTerminal() async throws
}

@MainActor
public final class WorkspaceSDKViewSurfaceActions: SDKViewSurfaceActions {
    public init() {}

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

    public func showCodingDictionary() throws {
        CodingDictionaryWindowManager.shared.showWindow()
    }

    public func showDatabaseExplorer() throws {
        SQLiteExplorerWindowManager.shared.showWindow()
    }

    public func showDocumentationBrowser() throws {
        DocumentationBrowserWindowManager.shared.showWindow()
    }

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

public final class SwiftCodeSDKViewHost: SDKViewHost, @unchecked Sendable {
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

    public static func unavailableError(viewID: String) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "The view “\(viewID)” is not available in this release.",
            suggestion: unavailableReasons[viewID] ?? "No host surface exists for this view in SwiftCode."
        )
    }
}

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
        await SDKAssistService.shared.setBackend(backend)
        await SDKBootstrap.bootstrapIfNeeded()
    }
}
