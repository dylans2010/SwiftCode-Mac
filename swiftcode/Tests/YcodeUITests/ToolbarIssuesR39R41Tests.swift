import AppKit
import Foundation
import Testing
import YcodeBuild
@testable import YcodeIDECore
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct ToolbarIssuesR39R41Tests {
    func scratch(_ name: String) -> URL {
        swiftcodeDir.appendingPathComponent(".build-ide/r39/\(name)-\(UUID().uuidString)")
    }

    func window(_ session: WorkspaceSession) -> WorkspaceWindowController {
        _ = NSApplication.shared
        let wc = WorkspaceWindowController(session: session, loadDestinations: false, startLanguageService: false)
        wc.window?.appearance = NSAppearance(named: .aqua)
        wc.applyDefaultLayout()
        return wc
    }

    @Test func issueNavigatorGroupsByTargetAndMergesCopies() throws {
        let dir = scratch("n1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let proj = try writeToolProject(at: dir)
        let session = WorkspaceSession(model: try WorkspaceModel(url: proj))
        let wc = window(session)
        let greeter = proj.deletingLastPathComponent().appendingPathComponent("Tool/Greeter.swift").path
        let build = Diagnostic(severity: .warning, message: "initialization of immutable value 'unused' was never used",
                               location: .init(file: greeter, line: 2, column: 9))
        session.issues = [build]
        session.notify(.issues)
        #expect(session.displayedIssues.map(\.message) == ["Initialization of immutable value 'unused' was never used"])
        let g = session.issueGrouping
        #expect(g.projectName == "Tool" && g.targetOrder == ["Tool"] && g.targetsOfFile(greeter) == ["Tool"])
        #expect(g.targetsOfFile(proj.deletingLastPathComponent().appendingPathComponent("Elsewhere.swift").path).isEmpty)
        let rows = wc.navigator.rows(4)
        #expect(rows.map(\.title) == ["Tool"] && rows.first?.detail == "1 issue")
        #expect(rows.first?.children.map(\.title) == ["Greeter"])
        #expect(rows.first?.children.first?.children.map(\.title) == ["Initialization of immutable value 'unused' was never used"])
        #expect(wc.issueCapsule.warnings == 1 && wc.issueCapsule.errors == 0)
        #expect(session.liveIssuesHiddenFiles == [IssueMerge.canonicalPath(greeter)])
        session.noteFileEdited(greeter)
        #expect(session.liveIssuesHiddenFiles.isEmpty)
    }

    struct ScriptedEngine: BuildEngine {
        let events: [BuildEvent]
        var name: String { "scripted" }
        func start(_ request: BuildRequest) -> BuildOperation {
            let (s, c) = AsyncStream<BuildEvent>.makeStream()
            for e in events { c.yield(e) }
            c.yield(.finished(BuildResult(status: .succeeded, exitCode: 0, issues: [])))
            c.finish()
            return BuildOperation(events: s, cancel: {})
        }
    }

    @Test func activityViewShowsBuildProgressWithSpinner() async throws {
        let dir = scratch("t4")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkspaceSession(model: try WorkspaceModel(url: try writeToolProject(at: dir)))
        let wc = window(session)
        var seen: [String] = []
        var spinning: [Bool] = []
        session.observe { change in
            guard change == .activity, case .building(let s) = session.activity else { return }
            seen.append(s)
            spinning.append(wc.activityView.showsSpinner)
        }
        session.engine = ScriptedEngine(events: [.planning, .activity("Compile main.swift"), .progress(done: 0, total: 3),
                                                 .activity("Compile Greeter.swift"), .progress(done: 2, total: 3), .progress(done: 3, total: 4)])
        let result = await session.build(.build)
        #expect(result.status == .succeeded)
        #expect(seen == ["Build", "Building \u{2022} Planning deferred tasks", "Building \u{2022} 0/3", "Building \u{2022} 2/3", "Building \u{2022} 3/4"])
        #expect(spinning.dropFirst().allSatisfy { $0 })
        #expect(!wc.activityView.showsSpinner && wc.activityView.status.hasPrefix("Build Succeeded \u{2022} Today at "))
        let long = "Finished running MyApp on iPhone 18 Pro Max"
        let short = ActivityView.truncatedStatus(long, width: 120)
        #expect(short.contains("\u{2026}") && short.first == "F" && short.hasSuffix("x"))
        #expect(ActivityView.truncatedStatus("Build", width: 120) == "Build")
    }

    @Test func toolbarTitlesAndIssueCapsuleButtons() throws {
        let dir = scratch("t6")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkspaceSession(model: try WorkspaceModel(url: try writeToolProject(at: dir)))
        let wc = window(session)
        let ids = wc.toolbarDefaultItemIdentifiers(NSToolbar()).map(\.rawValue)
        #expect(!ids.contains("account") && ids.last == "inspectorToggle")
        #expect(Array(ids.suffix(7)) == ["addEditor", "editorOptions", "editorModes", "extensions",
                                         "NSToolbarInspectorTrackingSeparatorItemIdentifier",
                                         "NSToolbarFlexibleSpaceItem", "inspectorToggle"])
        let add = try #require(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("addEditor"), willBeInsertedIntoToolbar: false))
        let opts = try #require(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("editorOptions"), willBeInsertedIntoToolbar: false))
        #expect(add.label == "Add Editor" && add.toolTip == "Add Editor Tabs or Editor Panes")
        #expect(opts.label == "Editor Options" && opts.toolTip == "Adjust Editor Options")
        #expect(wc.schemePopUp.accessibilityTitle() == "Active Scheme" && wc.destinationPopUp.accessibilityTitle() == "Active Run Destination")
        #expect(wc.inspectorToggleItemTitle == "Hide Inspector")
        wc.inspectorItem.isCollapsed = true
        #expect(wc.inspectorToggleItemTitle == "Show Inspector")
        let toggle = try #require(wc.debugArea.debugAreaToggle)
        #expect(toggle.toolTip == "show debug area" && toggle.accessibilityTitle() == "show debug area")
        wc.showDebugArea(true)
        #expect(toggle.toolTip == "hide debug area" && toggle.accessibilityTitle() == "hide debug area")
        let cap = wc.issueCapsule
        cap.errors = 0; cap.warnings = 2
        #expect(cap.buttons.map { $0.accessibilityTitle() ?? "" } == ["Errors", "Issues", "Test Failures"])
        #expect(cap.buttons.map(\.isHidden) == [true, false, true] && cap.buttons[1].title == "2")
        wc.navigator.select(0)
        cap.buttons[1].performClick(nil)
        #expect(wc.navigator.selectedIndex == 4 && wc.shownLeftPane == .navigators)
    }

    @Test func destinationPopUpShowsTheNameOnly() throws {
        let dir = scratch("t2")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkspaceSession(model: try WorkspaceModel(url: try writeToolProject(at: dir)))
        let wc = window(session)
        let sim = Destination(name: "iPhone 18 Pro", specifier: "platform=iOS Simulator,id=S1", platform: "iOS", kind: .simulator,
                              osVersion: "27.0", identifier: "S1")
        let wide = Destination(name: "iPad Pro 13-inch (M5) with a long name", specifier: "platform=iOS Simulator,id=S2", platform: "iOS",
                               kind: .simulator, osVersion: "27.0", identifier: "S2")
        wc.setDestinationGroups(DestinationCatalog.groups(devices: [], simulators: [sim, wide]))
        session.destination = sim
        wc.rebuildDestinationMenu()
        let popUp = wc.destinationPopUp
        #expect(wc.destinationTitle == "iPhone 18 Pro")
        let row = try #require(popUp.selectedItem)
        #expect(row.attributedTitle == nil)
        let width = popUp.intrinsicContentSize.width
        #expect(width < 160)
        let probe = NSPopUpButton(frame: .zero, pullsDown: false)
        probe.isBordered = false
        probe.controlSize = .small
        probe.addItem(withTitle: wide.name)
        #expect(width < probe.intrinsicContentSize.width)
        let menu = try #require(popUp.menu)
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(row.attributedTitle?.string == "iPhone 18 Pro\t27.0")
        menu.delegate?.menuDidClose?(menu)
        #expect(row.attributedTitle == nil && popUp.titleOfSelectedItem == "iPhone 18 Pro")
    }

    @Test func toolbarOverflowsInOrder() throws {
        let dir = scratch("t1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkspaceSession(model: try WorkspaceModel(url: try writeToolProject(at: dir)))
        let wc = window(session)
        let sim = Destination(name: "iPhone 18 Pro Max", specifier: "platform=iOS Simulator,id=S1", platform: "iOS", kind: .simulator,
                              osVersion: "27.0", identifier: "S1")
        wc.setDestinationGroups(DestinationCatalog.groups(devices: [], simulators: [sim]))
        session.destination = sim
        wc.rebuildDestinationMenu()
        wc.schemePopUp.removeAllItems()
        wc.schemePopUp.addItem(withTitle: "A Rather Long Scheme Name For Testing")
        wc.issueCapsule.errors = 1
        wc.issueCapsule.warnings = 2
        wc.activityView.status = "Build Succeeded \u{2022} Today at 1:17 PM"
        let window = try #require(wc.window)
        var fits: [Int: ToolbarFit] = [:]
        for w in [1600, 1400, 1250, 1150, 1100, 1050, 2000] {
            window.setFrame(NSRect(x: 0, y: 0, width: CGFloat(w), height: 900), display: false)
            wc.fitToolbar()
            let overflow = wc.overflowedToolbarItems
            print("toolbar \(w): \(wc.toolbarFit) overflow \(overflow) scheme \(wc.schemeCapsuleWidth)")
            #expect(Set(overflow).isSubset(of: ["editorModes", "history", "activity", "newConversation"]), "overflow at \(w): \(overflow)")
            if overflow.contains(where: { $0 != "editorModes" }) {
                #expect(wc.toolbarFit == ToolbarFit.steps(activityNatural: wc.activityView.naturalWidth).last, "at \(w)")
            }
            let visible = (window.toolbar?.visibleItems ?? []).map(\.itemIdentifier.rawValue)
            #expect(visible.last == "inspectorToggle")
            #expect(Set(["addEditor", "editorOptions", "scheme", "issues"]).isSubset(of: Set(visible)))
            #expect(wc.schemeShowsGlyphsOnly == wc.toolbarFit.schemeGlyphsOnly)
            if w == 1100 { #expect(!visible.contains("editorModes")) }
            fits[w] = wc.toolbarFit
        }
        #expect(fits[2000] == ToolbarFit() && wc.overflowedToolbarItems.isEmpty && !wc.schemeShowsGlyphsOnly)
        #expect(fits[1100]?.editorModesInOverflow == true && fits[1100]?.schemeGlyphsOnly == true)
        let order = [1600, 1400, 1250, 1150, 1100, 1050].compactMap { fits[$0] }
        let steps = ToolbarFit.steps(activityNatural: wc.activityView.naturalWidth)
        let ranks = order.compactMap { steps.firstIndex(of: $0) }
        #expect(ranks.count == order.count && ranks == ranks.sorted())
        let item = try #require(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "editorModes" })
        #expect(item.visibilityPriority == .low)
        #expect(item.menuFormRepresentation?.title == "Editor Modes")
        #expect(item.menuFormRepresentation?.submenu?.items.map(\.title) == ["Canvas", "Assistant", "Code Review"])
    }

    @Test func schemeCapsuleGlyphsOnly() throws {
        let dir = scratch("t1g")
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = WorkspaceSession(model: try WorkspaceModel(url: try writeToolProject(at: dir)))
        let wc = window(session)
        wc.schemePopUp.removeAllItems()
        wc.schemePopUp.addItem(withTitle: "A Rather Long Scheme Name For Testing")
        wc.schemePopUp.lastItem?.image = NSImage(size: NSSize(width: 16, height: 16))
        let full = wc.schemeCapsuleWidth
        wc.setSchemeGlyphsOnly(true)
        let glyphs = wc.schemeCapsuleWidth
        print("scheme capsule: titles \(full), glyphs \(glyphs)")
        #expect(glyphs < full)
        if #available(macOS 26, *) { #expect(abs(glyphs - 87) <= 4, "glyphs-only capsule \(glyphs)") }
        #expect(wc.schemePopUp.toolTip == "A Rather Long Scheme Name For Testing")
        wc.setSchemeGlyphsOnly(false)
        #expect(wc.schemeCapsuleWidth == full && wc.schemePopUp.toolTip == nil)
    }
}
