import Foundation
import SwiftUI
import YcodeIDECore
import YcodeIDEShell
#if os(Linux)
import OVPlatform
#endif

extension ShellDriver {
    #if os(Linux)
    static func scmWalk(_ app: ShellAppModel, prefix: String) async {
        guard let w = app.workspace else { say("scm: no workspace"); return }
        let scm = w.sourceControl
        func shot(_ name: String) async {
            await pause(0.7)
            let s = scm.snapshot
            say("scm \(name): branch=\(s.currentBranch ?? "-") changes=\(s.changes.count) pane=\(String(describing: scm.pane)) "
                + "busy=\(scm.busy ?? "-") error=\(scm.errorMessage ?? "-") " + OpenViewsAutomation.screenshot(to: "\(prefix)-scm-\(name).png"))
        }
        func waitIdle() async {
            for _ in 0..<200 {
                await pause(0.1)
                if scm.busy == nil { break }
            }
            await scm.idle()
        }
        if let first = scm.snapshot.changes.first, let ids = w.root.idPath(to: scm.workspacePath(first.path)) {
            for id in ids.dropLast() { w.setExpanded(id, true) }
        }
        await shot("project-badges")
        await click("selector 1")
        await waitIdle()
        await shot("changes")
        if let root = scm.repository?.root {
            let before = scm.snapshot.changes.count
            try? "Written outside SwiftCode.\n".write(to: root.appendingPathComponent("NOTES.txt"), atomically: true, encoding: .utf8)
            for _ in 0..<40 where scm.snapshot.changes.count == before { await pause(0.1) }
            say("scm watcher: changes \(before) -> \(scm.snapshot.changes.count)")
        }
        if let c = scm.snapshot.changes.first {
            let title = SourceControlRows.changeTitle(c.path, root: scm.repository?.root)
            let texts = OpenViewsAutomation.texts().filter { !$0.inPopup && $0.text == title && inNavigator($0.frame) }
            say("scm: \(texts.count) texts \(title) at \(texts.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY))" }); row frame \(frame("scm row \(title)").map { "\($0)" } ?? "-")")
            if let t = texts.last {
                await OpenViewsAutomation.click(at: CGPoint(x: t.frame.minX + 10, y: t.frame.midY))
                await pause(0.4)
            }
            say("scm: selection=\(scm.selection ?? "-") pane=\(String(describing: scm.pane)) collapsed=\(scm.collapsed)")
            await waitIdle()
        }
        await shot("commit-editor")
        await click("scm message")
        OpenViewsAutomation.type("Describe the change")
        await pause(0.4)
        await shot("commit-message")
        if let card = scm.cards.first {
            await click("scm card stage \(card.title)")
            await waitIdle()
        }
        await click("scm scope 2")
        await waitIdle()
        await shot("staged-scope")
        await click("scm scope 0")
        await waitIdle()
        await click("scm commit")
        await waitIdle()
        await shot("committed")
        if !scm.snapshot.changes.isEmpty {
            await clickText("Integrate", inPopup: false)
            await shot("integrate-menu")
            OpenViewsAutomation.press(.escape)
            await pause(0.3)
            w.perform(.scmCommit)
            await pause(0.5)
            if frame("commit sheet message") != nil { await click("commit sheet message") }
            OpenViewsAutomation.type("Commit the rest")
            await shot("commit-sheet")
            await click("commit sheet commit")
            await waitIdle()
            if scm.commitSheet != nil {
                scm.commitSheet?.message = "Commit the rest"
                scm.commitSheetFiles()
                await waitIdle()
            }
            await shot("after-commit-sheet")
        }
        await click("scm mode 1")
        await waitIdle()
        await shot("repositories")
        scm.choose(.newBranch(from: nil))
        await pause(0.5)
        if frame("scm prompt field 0") != nil { await click("scm prompt field 0") }
        OpenViewsAutomation.type("feature/linux-scm")
        await shot("new-branch-prompt")
        await click("scm prompt confirm")
        await waitIdle()
        if scm.prompt != nil {
            scm.prompt?.fields[0].text = "feature/linux-scm"
            scm.confirmPrompt()
            await waitIdle()
        }
        await shot("new-branch")
        if let main = frame("scm row main") {
            await OpenViewsAutomation.click(at: CGPoint(x: main.midX, y: main.midY), button: 3)
            await pause(0.5)
            await shot("branch-menu")
            OpenViewsAutomation.press(.escape)
            await pause(0.3)
        }
        await click("scm row main")
        await waitIdle()
        await shot("history")
        if let c = scm.history.first {
            await click("scm commit \(c.shortHash)")
            await waitIdle()
        }
        await shot("commit-detail")
        scm.choose(.checkout("main"))
        await pause(0.5)
        await shot("checkout-question")
        if let choice = scm.confirmation?.choices.last { scm.confirm(choice) }
        await waitIdle()
        if scm.hasRemote {
            w.perform(.scmPush)
            await waitIdle()
            await shot("pushed")
            w.perform(.scmPull)
            await waitIdle()
            await shot("pulled")
        }
        let file = w.root.allFiles.first { $0.name.hasSuffix(".swift") && ($0.path ?? "").contains("/Sources/") }
        if let p = file?.path {
            await click("selector 0")
            w.open(p)
            await pause(0.4)
            if let b = w.editor?.buffer {
                b.setCaret(0)
                b.insertText("// A new first line.\n")
                if b.lineCount > 6 {
                    b.selectLine(number: 6)
                    b.insertText("    // Changed line.\n")
                }
            }
            await pause(0.8)
            await scm.idle()
            await click("inspector tab 1")
            await waitIdle()
            await shot("change-bars-history")
        }
        w.closeCurrentDocument(discard: true)
        w.discardAllRecoveryCopies()
        say("scm walk done: \(scm.snapshot.branches.map(\.name)) head=\(scm.snapshot.head?.prefix(7) ?? "-")")
    }
    #endif
}
