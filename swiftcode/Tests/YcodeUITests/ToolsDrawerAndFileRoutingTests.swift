import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
import YcodeProject
@testable import YcodeUI
import YcodeIDEShell
import YcodeAssistant

@MainActor
@Suite(.serialized) struct ToolsDrawerAndFileRoutingTests {
    func makeWorkspace() throws -> WorkspaceWindowController {
        _ = NSApplication.shared
        let model = try WorkspaceModel(url: try WindowSnapshotTests().samplePackage())
        return WorkspaceWindowController(session: WorkspaceSession(model: model), loadDestinations: false,
                                         startLanguageService: false, openFirstFile: false)
    }

    @Test func toolsButtonInEditorToolbar() throws {
        let wc = try makeWorkspace()
        defer { wc.window?.close() }
        let ids = wc.toolbarDefaultItemIdentifiers(NSToolbar()).map(\.rawValue)
        #expect(ids.contains("toolsDrawer"), "Toolbar identifiers should contain toolsDrawer: \(ids)")
        
        let item = try #require(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("toolsDrawer"), willBeInsertedIntoToolbar: false))
        #expect(item.label == "Tools")
        #expect(item.toolTip == "Developer Tools Drawer")
        #expect(item.action == NSSelectorFromString("toggleToolsDrawer:"))
        #expect(item.isBordered)
        #expect(item.visibilityPriority == .high)
    }

    @Test func toolsRegistryContainsRequiredTools() {
        let registry = SCToolsRegistry.shared
        let toolIDs = Set(registry.tools.map(\.id))
        let required = ["symbols", "artboards", "database", "virtualization", "deviceConnect", "ipaPackaging", "codingDictionary", "ciWorkflows", "terminal"]
        for req in required {
            #expect(toolIDs.contains(req), "Missing tool: \(req)")
        }
    }

    @Test func structuredEditorsHandlesSupportedFileTypes() {
        #expect(StructuredEditor.handles("Info.plist"))
        #expect(StructuredEditor.handles("App.entitlements"))
        #expect(StructuredEditor.handles("Localizable.xcstrings"))
        #expect(StructuredEditor.handles("Assets.xcassets"))
        #expect(StructuredEditor.handles("Main.storyboard"))
        #expect(StructuredEditor.handles("LaunchScreen.xib"))
        #expect(StructuredEditor.handles("MyProject.xcodeproj"))
        #expect(!StructuredEditor.handles("main.swift"))
        #expect(!StructuredEditor.handles("Package.resolved"))
    }

    @Test func virtualizationRegistryRealDiskScan() throws {
        let registry = VirtualMachineRegistry.shared
        let dir = registry.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let testDisk = dir.appendingPathComponent("ubuntu-test-disk.img")
        let dummyData = Data(repeating: 0xAA, count: 1024)
        try dummyData.write(to: testDisk)
        defer { try? FileManager.default.removeItem(at: testDisk) }
        
        registry.scanVirtualDiskFiles()
        let records = registry.all()
        #expect(records.contains { $0.imagePath == testDisk.path })
        let found = records.first { $0.imagePath == testDisk.path }
        #expect(found?.osType == "Ubuntu")
    }
}
