import AppKit
import Foundation
import Testing
import YcodeBuild
import YcodeDebug
@testable import YcodeIDECore
import YcodeXcodebuild
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized, .heavyIntegration) struct SettingsTests {

    @Test func locationsPanePopUp() throws {
        _ = NSApplication.shared
        let t = TestDefaults("settings")
        defer { t.remove() }
        let d = t.defaults
        let c = SettingsController(defaults: d)
        var chosen: BuildSystemPreference?
        c.onChange = { chosen = $0 }
        _ = c.view
        #expect(c.buildSystemPopUp.itemTitles == ["xcodebuild", "swift-build (Default)"])
        #expect(c.buildSystemPopUp.indexOfSelectedItem == 1)
        c.choose(.xcodebuild)
        #expect(chosen == .xcodebuild && BuildSystemPreference.current(d) == .xcodebuild)
        let window = NSWindow(contentRect: c.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = c.view
        _ = try WindowSnapshotTests().render(c.view, to: "settings-locations.png")
    }

    @Test func defaultWithoutSwbuildIsConsistent() throws {
        _ = NSApplication.shared
        let t = TestDefaults("settings")
        defer { t.remove() }
        let d = t.defaults
        let c = SettingsController(defaults: d, locateSwiftBuild: { nil })
        _ = c.view
        #expect(c.buildSystemPopUp.titleOfSelectedItem == "swift-build (Default)")
        #expect(c.noteLabel.stringValue.contains("Builds use xcodebuild until then"))
        #expect(c.effectiveEngineName == "xcodebuild")
        let window = NSWindow(contentRect: c.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = c.view
        _ = try WindowSnapshotTests().render(c.view, to: "settings-locations-no-swbuild.png")
        let found = SettingsController(defaults: d, locateSwiftBuild: { "/opt/swbuild" })
        _ = found.view
        #expect(found.noteLabel.stringValue == "swbuild: /opt/swbuild" && found.effectiveEngineName == "swift-build")
        c.choose(.xcodebuild)
        #expect(c.noteLabel.stringValue == "Builds use xcodebuild." && c.effectiveEngineName == "xcodebuild")
    }

    @Test(.timeLimit(.minutes(15))) func runWithSwiftBuild() async throws {
        _ = NSApplication.shared
        let probe = swiftcodeDir.appendingPathComponent("Tools/swiftcode-swb/.build/debug/swbuild").path
        guard let tool = SwiftBuildEngine.locate() ?? (FileManager.default.isExecutableFile(atPath: probe) ? probe : nil),
              LLDBDAP.locate() != nil else { return }
        let lock = await InterprocessLock.acquire(path: InterprocessLock.debuggerTestLockPath)
        defer { lock.unlock() }
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/run-swiftbuild")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Tool"), withIntermediateDirectories: true)
        let fixture = swiftcodeDir.appendingPathComponent(".build-ide/pif-unit/Tool.xcodeproj")
        try FileManager.default.copyItem(at: fixture, to: dir.appendingPathComponent("Tool.xcodeproj"))
        try "#include <stdio.h>\nint main(void) { printf(\"ran via swift-build\\n\"); return 0; }\n"
            .write(to: dir.appendingPathComponent("Tool/main.c"), atomically: true, encoding: .utf8)
        let session = WorkspaceSession(model: try WorkspaceModel(url: dir.appendingPathComponent("Tool.xcodeproj")))
        session.engine = BuildSystemPreference.swiftBuild.makeEngine(locateSwiftBuild: { tool })
        let wc = WorkspaceWindowController(session: session, loadDestinations: false, startLanguageService: false)
        _ = wc
        let request = session.model.buildRequest(scheme: session.scheme, destination: session.destination, action: .build)
        let exe = try #require(session.engine.executablePath(for: request))
        #expect(exe.hasSuffix(".swiftcode-build/Products/Debug/Tool"))
        await session.run(program: exe)
        let exited = await waitUntil(480) { session.console.contains("exit code: 0") }
        #expect(exited, "console: \(session.console.suffix(2000)) build: \(session.reports.first.map { "\($0.succeeded) " + $0.log.suffix(30).joined(separator: "\n") } ?? "none")")
        #expect(session.reports.first?.succeeded == true)
    }
}
