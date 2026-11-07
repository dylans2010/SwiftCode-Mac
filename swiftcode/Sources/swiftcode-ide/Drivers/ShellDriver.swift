import Foundation
import SwiftUI
import SwiftCodeIDEShell
#if os(Linux)
import OVPlatform
#endif

@MainActor
enum ShellDriver {
    static let env = ProcessInfo.processInfo.environment

    static func say(_ s: String) {
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    static func state(_ app: ShellAppModel) -> String {
        guard let w = app.workspace else { return "state: welcome recent=\(app.recent.count)" }
        let c = w.issueCounts
        return "state: workspace=\(w.workspaceName) navigator=\(w.navigator.rawValue) document=\(w.document?.name ?? "none") "
            + "lines=\(w.editor?.buffer.lineCount ?? 0) edited=\(w.editedPaths.count) caret=\(w.editor.map { "\($0.buffer.caretLine + 1):\($0.buffer.caretColumn + 1)/\($0.buffer.selection.range.count)" } ?? "-") length=\(w.editor?.buffer.length ?? 0) findbar=\(w.findBar.isShown ? "\"" + w.findBar.countText + "\"" : "hidden") jump=\(w.isJumpToLineShown) alert=\(w.saveAlert != nil) marked=\(w.markedLine.map(String.init) ?? "none") "
            + "find=\"\(w.findText)\" results=\"\(w.findCountText)\" issues=\(c.errors)E/\(c.warnings)W "
            + "activity=\"\(w.activityText)\" builds=\(w.buildCount) debugArea=\(w.isDebugAreaShown) "
            + "inspector=\(w.isInspectorShown) navigatorShown=\(w.isNavigatorShown) findFocus=\(w.findFocusCount) bezel=\"\(w.notifier.bezel?.title ?? "")\""
    }

    #if os(Linux)
    static var started = false

    static func start(_ app: ShellAppModel) async {
        guard !started else { return }
        started = true
        let switches = ["OV_PRINT_TARGETS", "OV_QUIT_AFTER", "SWIFTCODE_IDE_SCRIPT", "SWIFTCODE_IDE_PARITY", "SWIFTCODE_IDE_REMOTE_RUN", "SWIFTCODE_IDE_WALK",
                        "SWIFTCODE_IDE_DEBUG", "SWIFTCODE_IDE_SCM", "SWIFTCODE_IDE_TESTS", "SWIFTCODE_IDE_RUNTIME_WALK", "SWIFTCODE_IDE_SETTINGS",
                        "SWIFTCODE_IDE_SETTINGS_VERIFY", "SWIFTCODE_IDE_EDITORS", "SWIFTCODE_IDE_LSP",
                        "SWIFTCODE_IDE_IME", "SWIFTCODE_IDE_POLISH", "SWIFTCODE_IDE_DEBUG2", "SWIFTCODE_IDE_ASSISTANT",
                        "SWIFTCODE_IDE_DOWNLOAD_WALK", "SWIFTCODE_IDE_ACCOUNTS", "SWIFTCODE_IDE_CONFLICT", "SWIFTCODE_IDE_SIMDEBUG", "SWIFTCODE_IDE_SIMUX", "SWIFTCODE_IDE_ORGANIZER", "SWIFTCODE_IDE_IB", "SWIFTCODE_IDE_PREVIEWS",
                        "SWIFTCODE_IDE_GLASS4"]
        guard switches.contains(where: { env[$0] != nil }) else { return }
        await pause(0.4)
        say("backend \(OpenViewsAutomation.backendName)")
        if let s = OpenViewsAutomation.windowSize() {
            say("window \(s.points.width)x\(s.points.height) pt, pixels \(s.pixels.width)x\(s.pixels.height)")
        }
        say("menus: \(OpenViewsAutomation.menuTitles())")
        say(state(app))
        if env["OV_PRINT_TARGETS"] != nil { printTargets() }
        if env["SWIFTCODE_IDE_SCRIPT"] != nil { await script(app) }
        if let prefix = env["SWIFTCODE_IDE_PARITY"] { await parity(app, prefix: prefix) }
        if let file = env["SWIFTCODE_IDE_EDITOR_BENCH"] { await EditorBench.run(app, file: file) }
        if let name = env["SWIFTCODE_IDE_REMOTE_RUN"] { await remoteRun(app, destination: name) }
        if let prefix = env["SWIFTCODE_IDE_WALK"] { await walk(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_EDITORS"] { await EditorsDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_IB"] { await InterfaceBuilderDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_SETTINGS"] { await SettingsDriver.run(app, prefix: prefix) } else if env["SWIFTCODE_IDE_SETTINGS_VERIFY"] != nil { say(SettingsDriver.values()) }
        if let prefix = env["SWIFTCODE_IDE_ACCOUNTS"] { await AccountsDriver.run(prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_ORGANIZER"] { await OrganizerDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_LSP"] { await LanguageDriver.run(app, prefix: prefix) }
        if env["SWIFTCODE_IDE_IME"] != nil { await prepareInputMethodTest(app) }
        if let prefix = env["SWIFTCODE_IDE_DEBUG"] { await DebugDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_POLISH"] { await polish(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_DEBUG2"] { await DebugEditingDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_SIMDEBUG"] { await SimDebugDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_PREVIEWS"] { await PreviewsDriver.run(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_GLASS4"] {
            await glass4Walk(app, prefix: prefix)
            OpenViewsAutomation.terminate()
        }
        if let prefix = env["SWIFTCODE_IDE_SCM"] {
            await scmWalk(app, prefix: prefix)
            OpenViewsAutomation.terminate()
        }
        if let prefix = env["SWIFTCODE_IDE_CONFLICT"] {
            await conflictWalk(app, prefix: prefix)
            OpenViewsAutomation.terminate()
        }
        if let prefix = env["SWIFTCODE_IDE_ASSISTANT"] {
            await assistantWalk(app, prefix: prefix)
            OpenViewsAutomation.terminate()
        }
        if let prefix = env["SWIFTCODE_IDE_TESTS"] {
            await testsWalk(app, prefix: prefix)
            OpenViewsAutomation.terminate()
        }
        if let prefix = env["SWIFTCODE_IDE_RUNTIME_WALK"] { await runtimeWalk(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_DOWNLOAD_WALK"] { await downloadWalk(app, prefix: prefix) }
        if let prefix = env["SWIFTCODE_IDE_SIMUX"] { await simulatorWalk(app, prefix: prefix) }
        if let s = env["OV_QUIT_AFTER"], let t = Double(s) {
            var elapsed = 0.0
            while elapsed < t {
                await pause(0.25)
                elapsed += 0.25
                if let req = env["OV_SHOT_REQUEST"], let path = try? String(contentsOfFile: req, encoding: .utf8) {
                    try? FileManager.default.removeItem(atPath: req)
                    let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let colon = p.firstIndex(of: ":"), let n = Int(p[..<colon]) {
                        say(OpenViewsAutomation.screenshot(n, to: String(p[p.index(after: colon)...])))
                    } else {
                        say(OpenViewsAutomation.screenshot(to: p))
                    }
                }
                if Int(elapsed * 4) % 4 == 0 || env["SWIFTCODE_IDE_STATE_FAST"] != nil {
                    if env["OV_PRINT_TARGETS"] != nil { printTargets() }
                    say(state(app))
                }
            }
            if let path = env["OV_SCREENSHOT"] { say(OpenViewsAutomation.screenshot(to: path)) }
            say(state(app))
            OpenViewsAutomation.terminate()
        }
    }

    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }

    static var scale: Double {
        guard let s = OpenViewsAutomation.windowSize(), s.points.width > 0 else { return 1 }
        return Double(s.pixels.width) / s.points.width
    }

    static func printTargets() {
        for (name, f) in OpenViewsAutomation.identifiedFrames(1).sorted(by: { $0.key < $1.key }) {
            say(String(format: "w1target %@ %.0f %.0f %.0f %.0f", name.replacingOccurrences(of: " ", with: "_"), f.minX, f.minY, f.width, f.height))
        }
        let k = scale
        func line(_ name: String, _ f: CGRect) -> String {
            String(format: "target %@ %.0f %.0f %.0f %.0f pixels %.0f %.0f %.0f %.0f", name.replacingOccurrences(of: " ", with: "_"),
                   f.minX, f.minY, f.width, f.height, f.minX * k, f.minY * k, f.width * k, f.height * k)
        }
        let titles = Set(OpenViewsAutomation.menuTitles())
        var seen = Set<String>()
        for t in OpenViewsAutomation.texts() {
            let name = t.inPopup ? "item_" + t.text : (titles.contains(t.text) ? "menu_" + t.text : "")
            guard !name.isEmpty, t.frame.minY < 40 || t.inPopup, seen.insert(name).inserted else { continue }
            say(line(name, t.frame))
        }
        for (name, f) in OpenViewsAutomation.identifiedFrames().sorted(by: { $0.key < $1.key }) { say(line(name, f)) }
        for t in OpenViewsAutomation.texts() where !t.inPopup && inNavigator(t.frame) {
            guard seen.insert("row_" + t.text).inserted else { continue }
            say(line("row_" + t.text, t.frame))
        }
    }

    static func inNavigator(_ f: CGRect) -> Bool {
        let top = frame("selector 0")?.maxY ?? 100
        let right = frame("editor")?.minX ?? 290
        return f.minY > top + 4 && f.maxX < right
    }

    static func frame(_ name: String) -> CGRect? { OpenViewsAutomation.identifiedFrames()[name] }

    static func click(_ name: String, dx: CGFloat? = nil) async {
        guard let f = frame(name) else {
            say("no target \(name)")
            return
        }
        await OpenViewsAutomation.click(at: CGPoint(x: dx.map { f.minX + $0 } ?? f.midX, y: f.midY))
        await pause(0.35)
    }

    static func clickText(_ text: String, inPopup: Bool) async {
        guard let t = OpenViewsAutomation.texts().first(where: { $0.text == text && $0.inPopup == inPopup }) else {
            say("no text \(text)")
            return
        }
        await OpenViewsAutomation.click(at: CGPoint(x: t.frame.midX, y: t.frame.midY))
        await pause(0.4)
    }

    static func clickNavigatorText(_ text: String, dx: CGFloat) async {
        guard let t = OpenViewsAutomation.texts().first(where: { !$0.inPopup && $0.text == text && inNavigator($0.frame) })
        else {
            say("no navigator text \(text)")
            return
        }
        await OpenViewsAutomation.click(at: CGPoint(x: t.frame.minX + dx, y: t.frame.midY))
        await pause(0.35)
    }

    static func clickProjectRow(_ w: WorkspaceShellModel, id: String, dx: CGFloat) async {
        let rows = w.projectRows
        guard let index = rows.firstIndex(where: { $0.id == id }) else {
            say("no project row \(id)")
            return
        }
        let title = rows[index].title
        let nth = rows[..<index].filter { $0.title == title }.count
        let texts = OpenViewsAutomation.texts().filter { !$0.inPopup && $0.text == title && inNavigator($0.frame) }
            .sorted { $0.frame.minY < $1.frame.minY }
        guard texts.indices.contains(nth) else {
            say("no navigator text \(title) (row \(nth + 1) with that title)")
            return
        }
        let f = texts[nth].frame
        await OpenViewsAutomation.click(at: CGPoint(x: f.minX + dx, y: f.midY))
        await pause(0.35)
    }

    static func shot(_ step: String) {
        if let p = env["SWIFTCODE_IDE_SHOT_PREFIX"] { say(OpenViewsAutomation.screenshot(to: "\(p)-\(step).png")) }
    }

    static func remoteRun(_ app: ShellAppModel, destination name: String) async {
        guard let w = app.workspace else { say("remote run: no workspace"); return }
        say("destinations: \(w.destinations.map(\.name))")
        guard let d = w.destinations.first(where: { $0.name == name }) else { say("remote run: no destination \(name)"); return }
        w.destination = d
        await pause(0.5)
        shot("remote-destination")
        await clickText("Product", inPopup: false)
        await clickText("Run", inPopup: true)
        for _ in 0..<240 {
            await pause(0.5)
            if w.console.contains("Installing and launching") || w.console.contains("failed") { break }
        }
        say("remote run console: \(w.console.split(separator: "\n").suffix(4).joined(separator: " | "))")
        await pause(1)
        shot("remote-run")
    }

    static func script(_ app: ShellAppModel) async {
        guard let w = app.workspace else {
            say("script: no workspace")
            return
        }
        func step(_ label: String) { say("step \(label): \(state(app))") }
        step("opened")
        shot("open")
        let target = env["SWIFTCODE_IDE_SCRIPT_FILE"].flatMap { name in w.root.allFiles.first { $0.name == name } }
            ?? w.root.allFiles.first { $0.name.hasSuffix(".swift") && ($0.path ?? "").contains("/Sources/") }
        if let file = target, let path = file.path, let ids = w.root.idPath(to: path) {
            for id in ids.dropLast() where !w.isExpanded(id) {
                await pause(0.3)
                await clickProjectRow(w, id: id, dx: -26)
            }
            await pause(0.3)
            await clickProjectRow(w, id: file.id, dx: 10)
            await pause(0.5)
        }
        step("selected a file")
        if let file = target {
            say("check selected a file: \(w.document?.name == file.name ? "ok" : "FAILED") (\(file.name))")
        }
        shot("file")
        OpenViewsAutomation.press(.character("f"), modifiers: [.control, .shift])
        await pause(0.4)
        OpenViewsAutomation.type(env["SWIFTCODE_IDE_FIND"] ?? "Greeting")
        await pause(0.2)
        OpenViewsAutomation.press(.return)
        for _ in 0..<40 where w.isSearching || w.findRows.isEmpty { await pause(0.1) }
        await pause(0.4)
        step("find in workspace")
        shot("find")
        await clickText("Product", inPopup: false)
        shot("product-menu")
        await clickText("Build", inPopup: true)
        await pause(0.5)
        for _ in 0..<600 where w.isBusy { await pause(0.25) }
        await pause(0.8)
        step("built")
        shot("build")
        if let first = w.allIssues.first(where: { $0.file != nil }) {
            await clickNavigatorText(first.message, dx: 20)
            await pause(0.6)
        }
        step("opened the first issue")
        shot("issue")
        await r13Steps(app)
        OpenViewsAutomation.terminate()
    }

    static func parity(_ app: ShellAppModel, prefix: String) async {
        func shot(_ state: String) async {
            await pause(0.6)
            say("parity \(state): " + OpenViewsAutomation.screenshot(to: "\(prefix)-\(state).png"))
        }
        guard let w = app.workspace else {
            await shot("welcome")
            OpenViewsAutomation.terminate()
            return
        }
        await shot("workspace")
        if let file = w.root.allFiles.first(where: { $0.name == (env["SWIFTCODE_IDE_SCRIPT_FILE"] ?? "Greeting.swift") }), let p = file.path {
            w.open(p)
        }
        await shot("file")
        w.isInspectorShown = false
        await shot("inspector-hidden")
        w.isInspectorShown = true
        w.perform(.findInWorkspace)
        w.findText = env["SWIFTCODE_IDE_FIND"] ?? "Greeting"
        w.runFind()
        await w.waitForFind()
        await shot("find")
        await clickText("Product", inPopup: false)
        await shot("product-menu")
        OpenViewsAutomation.press(.escape)
        OpenViewsAutomation.move(to: CGPoint(x: 700, y: 500))
        await pause(0.3)
        w.perform(.build)
        await pause(0.3)
        for _ in 0..<1200 where w.isBusy { await pause(0.1) }
        if w.notifier.bezel != nil { await shot("bezel") }
        for _ in 0..<60 where w.notifier.bezel != nil { await pause(0.1) }
        w.isDebugAreaShown = false
        w.navigator = .issues
        await shot("issues")
        w.isDebugAreaShown = true
        await shot("debug")
        w.isDebugAreaShown = false
        app.showOpenSheet()
        await shot("sheet")
        OpenViewsAutomation.press(.escape)
        await pause(0.3)
        OpenViewsAutomation.terminate()
    }

    static func walk(_ app: ShellAppModel, prefix: String) async {
        func shot(_ name: String) async {
            await pause(0.7)
            say("walk \(name): \(state(app)) " + OpenViewsAutomation.screenshot(to: "\(prefix)-\(name).png"))
        }
        func menu(_ title: String, _ name: String) async {
            await clickText(title, inPopup: false)
            await shot("menu-\(name)")
            OpenViewsAutomation.press(.escape)
            await pause(0.3)
        }
        guard let w = app.workspace else {
            await shot("welcome")
            await menu("SwiftCode", "swiftcode")
            await menu("Help", "help")
            app.perform(.about)
            await shot("about")
            app.isAboutShown = false
            await pause(0.8)
            app.perform(.clone)
            await shot("clone")
            if let c = app.clone {
                c.address = "file:///nonexistent/Repository.git"
                await c.clone().value
                await shot("clone-failed")
            }
            app.cancelClone()
            await pause(0.8)
            app.showNewProject()
            await shot("new-project")
            if let m = app.newProject {
                for tab in m.flow.tabs {
                    m.setPlatform(tab)
                    await shot("new-project-\(tab)")
                }
                m.setPlatform(m.flow.tabs[1])
                m.next()
                await shot("new-project-options")
            }
            app.cancelNewProject()
            await pause(0.8)
            app.notice = ShellNotice("Sample", "A long message that wraps over more than one line, to look at how the alert sets its text and where its button goes.")
            await shot("notice")
            app.notice = nil
            await pause(0.5)
            await click("welcome close")
            await pause(2)
            say("walk: still running after Close")
            OpenViewsAutomation.terminate()
            return
        }
        await shot("workspace")
        for i in 0..<9 {
            await click("selector \(i)")
            await shot("navigator-\(i)")
        }
        await click("selector 0")
        await menu("File", "file")
        await menu("Edit", "edit")
        await menu("View", "view")
        await menu("Find", "find")
        await menu("Navigate", "navigate")
        await menu("Editor", "editor")
        await menu("Product", "product")
        await menu("Debug", "debug")
        await menu("Integrate", "integrate")
        await menu("Window", "window")
        await menu("Help", "help")
        await click("tb destination")
        await shot("destination-menu")
        OpenViewsAutomation.press(.escape)
        await pause(0.3)
        w.perform(.build)
        await pause(0.5)
        while w.isBusy { await pause(0.1) }
        await shot("after-build")
        for _ in 0..<60 where w.notifier.bezel != nil { await pause(0.1) }
        await shot("after-build-settled")
        say("walk build log: \(w.buildLog.suffix(12).joined(separator: " | "))")
        w.perform(.test)
        await pause(0.5)
        while w.isBusy { await pause(0.1) }
        await shot("after-test")
        say("walk test log: \(w.buildLog.suffix(8).joined(separator: " | "))")
        w.perform(.run)
        for _ in 0..<240 {
            await pause(0.25)
            if !w.isBusy && !w.console.isEmpty { break }
        }
        await pause(1)
        await shot("after-run")
        say("walk run console: \(w.console.suffix(600))")
        OpenViewsAutomation.terminate()
    }

    static func r13Steps(_ app: ShellAppModel) async {
        guard let w = app.workspace else { return }
        OpenViewsAutomation.press(.character("1"), modifiers: [.control])
        await pause(0.4)
        say("step submenu shortcut: navigator=\(w.navigator.rawValue)")
        if let run = frame("tb run") {
            OpenViewsAutomation.move(to: CGPoint(x: run.midX, y: run.midY))
            await pause(1.4)
            let tip = OpenViewsAutomation.texts().first { $0.text == "Build and run the scheme" }
            say("step tooltip: \(tip.map { "shown at \(Int($0.frame.minX)),\(Int($0.frame.minY))" } ?? "none")")
            shot("tooltip")
            OpenViewsAutomation.move(to: CGPoint(x: run.midX, y: run.maxY + 200))
            await pause(0.3)
        }
        await clickText("View", inPopup: false)
        if let nav = OpenViewsAutomation.texts().first(where: { $0.inPopup && $0.text == "Navigators" }) {
            OpenViewsAutomation.move(to: CGPoint(x: nav.frame.midX, y: nav.frame.midY))
            await pause(0.3)
            await OpenViewsAutomation.click(at: CGPoint(x: nav.frame.midX, y: nav.frame.midY))
            await pause(0.5)
        }
        let items = OpenViewsAutomation.texts().filter(\.inPopup).map(\.text)
        say("step submenu: \(OpenViewsAutomation.openPopupCount) pop-ups, items \(items)")
        shot("submenu")
        OpenViewsAutomation.press(.escape)
        await pause(0.2)
        OpenViewsAutomation.press(.escape)
        await pause(0.4)
        OpenViewsAutomation.press(.character("o"), modifiers: [.control])
        await pause(0.8)
        say("step file dialog: shown=\(app.isOpenSheetShown) folder=\(OpenViewsAutomation.texts().first { $0.text.hasPrefix("/") }?.text ?? "?")")
        shot("file-dialog")
        if let field = frame("file dialog path") {
            await OpenViewsAutomation.click(at: CGPoint(x: field.midX, y: field.midY))
            await pause(0.3)
            OpenViewsAutomation.type(w.session.model.url.path)
            await pause(0.2)
            OpenViewsAutomation.press(.return)
            await pause(0.6)
            shot("file-dialog-folder")
            OpenViewsAutomation.press(.return)
            await pause(1.0)
        }
        say("step reopened: shown=\(app.isOpenSheetShown) \(state(app))")
        shot("reopened")
    }
    #else
    static func start(_ app: ShellAppModel) async {}
    #endif
}
