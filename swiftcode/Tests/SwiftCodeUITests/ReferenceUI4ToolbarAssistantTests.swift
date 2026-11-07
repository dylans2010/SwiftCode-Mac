import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct ReferenceUI4ToolbarAssistantTests {
    @Test func toolbarRightGroupAndOptionsMenu() throws {
        _ = NSApplication.shared
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/toolbar-right")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources/App"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: dir)), loadDestinations: false, startLanguageService: false)
        let ids = wc.toolbarDefaultItemIdentifiers(NSToolbar()).map(\.rawValue)
        #expect(!ids.contains("account"))
        let start = try #require(ids.firstIndex(of: "addEditor"))
        #expect(Array(ids[start..<(start + 3)]) == EditorOptionsMenu.rightGroup)
        let opts = try #require(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("editorOptions"), willBeInsertedIntoToolbar: false) as? NSMenuToolbarItem)
        #expect(opts.label == "Editor Options" && opts.toolTip == "Adjust Editor Options")
        #expect(opts.menu.items.map { $0.isSeparatorItem ? "|" : $0.title } == [
            "Layout", "|", "Inline Comparison", "Side By Side Comparison", "|", "Minimap", "Authors", "Code Coverage", "|",
            "Invisibles", "Scope Guides", "Wrap Lines", "|", "Choose Workspace Theme…"])
        #expect(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("addEditor"), willBeInsertedIntoToolbar: false)?.toolTip == "Add Editor Tabs or Editor Panes")
        let window = try #require(CommandTable.menus.first { $0.0 == "Window" }?.1)
        #expect(!window.contains { if case .command(let c) = $0 { c.title == "Devices and Simulators" } else { false } })
    }

    @Test func customModesInWindow() throws {
        _ = NSApplication.shared
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/assistant-modes")
        try? FileManager.default.removeItem(at: dir)
        let src = dir.appendingPathComponent("Sources/E")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"E\", targets: [.target(name: \"E\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "/// Doc.\npublic struct Model {\n    public func f() {}\n}\n".write(to: src.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try "extension Model {\n}\n".write(to: src.appendingPathComponent("Model+More.swift"), atomically: true, encoding: .utf8)
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: dir)), loadDestinations: false, startLanguageService: false)
        wc.applyDefaultLayout()
        wc.open(path: src.appendingPathComponent("Model.swift").path, line: nil)
        wc.toggleAssistant(nil)
        let a = try #require(wc.editorArea.tab.assistant)
        #expect(a.disabledAssistantModes.contains("Callers"))
        wc.setAssistantModeTitle("Extensions")
        #expect(a.fileURL?.lastPathComponent == "Model+More.swift")
        #expect(wc.assistantModeTitle == "Extensions")
        wc.setAssistantModeTitle("Generated Interface")
        #expect(a.textView.string.contains("public func f()") && !a.textView.string.contains("{}\n}"))
        wc.setAssistantModeTitle("Documentation Preview")
        #expect(a.textView.string.hasPrefix("Model"))
        wc.setAssistantModeTitle("Superclasses")
        #expect(a.textView.string == "No Editor")
        wc.setAssistantModeTitle("Counterparts")
        #expect(wc.assistantMode == .counterparts && wc.assistantModeTitle == "Counterparts")
    }
}
