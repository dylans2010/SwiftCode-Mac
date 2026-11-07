import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeIDEShell

@MainActor
@Suite(.serialized) struct ConflictEditorShellTests {
    static let colorsBase = "let background = \"white\"\nlet border = \"gray\"\nlet text = \"black\"\nlet link = \"blue\"\nlet accent = \"orange\"\n"
    static let q = { (s: String) in "\u{201C}\(s)\u{201D}" }

    func conflictingPackage() throws -> GitPackage {
        let g = try GitPackage()
        let colors = "Sources/DemoCore/Colors.swift", greeting = "Sources/DemoCore/Greeting.swift"
        try g.write(colors, Self.colorsBase)
        try g.git(["add", "-A"])
        try g.git(["commit", "-q", "-m", "Colors"])
        try g.git(["switch", "-q", "-c", "feature"])
        try g.write(colors, Self.colorsBase.replacingOccurrences(of: "white", with: "ivory").replacingOccurrences(of: "orange", with: "teal"))
        try g.write(greeting, "public func greeting() -> String { \"Welcome\" }\n")
        try g.git(["commit", "-q", "-am", "Feature"])
        try g.git(["switch", "-q", "main"])
        try g.write(colors, Self.colorsBase.replacingOccurrences(of: "white", with: "snow").replacingOccurrences(of: "orange", with: "purple"))
        try g.write(greeting, "public func greeting() -> String { \"Hi\" }\n")
        try g.git(["commit", "-q", "-am", "Main"])
        return g
    }

    static func gitPath(_ scm: SourceControlShellModel, _ name: String) -> String {
        scm.snapshot.changes.first { $0.path.hasSuffix("/" + name) }?.path ?? name
    }

    func model(_ g: GitPackage) async throws -> WorkspaceShellModel {
        let m = try WorkspaceShellModel(url: g.url, engine: ScriptedEngine(lines: [], issues: []))
        await m.sourceControl.idle()
        return m
    }

    func mergeFeature(_ scm: SourceControlShellModel) async throws -> ConflictEditorShellModel {
        scm.choose(.merge("feature"))
        scm.confirmMergeAlert()
        await scm.idle()
        let editor = try #require(scm.conflictEditor)
        await editor.idle()
        return editor
    }

    func chooseEverywhere(_ editor: ConflictEditorShellModel, _ choice: MergeDocument.Choice) async {
        for f in editor.state.files {
            await editor.show(file: f)
            for h in editor.state.document?.hunks.indices ?? 0..<0 where editor.state.token(forHunk: h)?.isConflict == true {
                editor.choose(choice, forHunk: h)
            }
        }
    }

    @Test func aMergeResolvedThroughChooseAndByHandMakesTheMergeCommit() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        let m = try await model(g)
        let scm = m.sourceControl
        scm.mode = .repositories
        let items = scm.menu(for: "branch:feature")
        #expect(items.first { $0.title == "Merge \(Self.q("feature")) into \(Self.q("main"))…" }?.isEnabled == true)
        #expect(items.first { $0.title == "Merge \(Self.q("main")) into \(Self.q("feature"))…" }?.isEnabled == false)
        #expect(items.compactMap(\.action).count == 12)

        scm.choose(.merge("feature"))
        let alert = try #require(scm.mergeAlert)
        #expect(scm.confirmation == nil && !alert.hasChooser)
        #expect(alert.title == "Are you sure you want to merge from \(Self.q("feature"))?")
        #expect(alert.message == "Changes from \(Self.q("feature")) will be merged into your current branch (\(Self.q("main"))).")
        #expect(alert.frame(window: (1400, 880)) == MergeSheetMetrics.Rect(x: 490, y: 373, width: 420, height: 133))
        scm.confirmMergeAlert()
        #expect(scm.mergeAlert == nil && scm.isMerging)
        await scm.idle()
        let colors = Self.gitPath(scm, "Colors.swift"), greeting = Self.gitPath(scm, "Greeting.swift")

        let editor = try #require(scm.conflictEditor)
        await editor.idle()
        #expect(scm.isMergeSheetShown && !scm.isMerging && scm.pane == nil && scm.notice == nil)
        var st = editor.state
        #expect(st.files == [colors, greeting] && st.currentFile == colors)
        #expect(st.sheetDocument(greeting) != nil, "every file is read ahead")
        #expect(st.stepperText == "1/2" && st.primaryTitle == "Merge" && !st.canMerge)
        #expect(st.token(forHunk: 0)?.glyph == "?" && st.token(forHunk: 0)?.isSelected == true)
        #expect(st.leftFooter?.branch == "main" && st.leftFooter?.isHead == true && st.leftFooter?.commitText.hasSuffix("(HEAD)") == true)
        #expect(st.rightFooter?.branch == "feature" && st.rightFooter?.isHead == false)
        #expect(editor.fileRows.map(\.title) == ["DemoCore", "Colors.swift", "Greeting.swift"])
        editor.isFlat = true
        #expect(editor.fileRows.map(\.title) == ["Colors.swift", "Greeting.swift"])
        editor.filterText = "greet"
        #expect(editor.fileRows.map(\.title) == ["Greeting.swift"])
        editor.isFlat = false
        editor.filterText = ""
        #expect(Array(editor.jumpPath.dropFirst()) == ["Sources", "DemoCore", "Colors"])
        #expect(m.isEnabled(.scmResolveConflicts) && m.isEnabled(.scmAbortIntegration) && !m.isEnabled(.scmMerge))
        #expect(scm.selectedFile == colors)

        editor.choose(.ours, forHunk: 0)
        st = editor.state
        #expect(st.currentHunk == 0 && st.stepperText == "1/2" && st.token(forHunk: 0)?.glyph == "2" && st.token(forHunk: 0)?.isDecided == true)
        editor.choose(.theirs, forHunk: 1)
        st = editor.state
        #expect(st.currentHunk == 1 && st.stepperText == "2/2" && st.token(forHunk: 1)?.glyph == "1")
        #expect(st.leftLines.contains("let background = \"snow\"") && st.leftLines.contains("let accent = \"teal\""))
        #expect(st.rightLines.contains("let accent = \"teal\"") && !st.canMerge)
        editor.previousHunk()
        #expect(editor.state.currentHunk == 0 && editor.revealCount == 1)

        await editor.show(file: greeting)
        #expect(editor.state.currentFile == greeting && editor.state.token(forHunk: 0)?.glyph == "?")
        editor.selectHunk(0)
        editor.beginEditing()
        #expect(editor.state.isEditing && editor.editedText.contains("Hi") && editor.editedText.contains("Welcome"))
        editor.editedText = "public func greeting() -> String { \"Greetings\" }\n"
        #expect(editor.state.token(forHunk: 0)?.glyph == "7")
        #expect(editor.state.isDecided(file: colors) && editor.state.canMerge)
        await editor.show(file: colors)
        #expect(editor.state.token(forHunk: 0)?.glyph == "2" && editor.state.token(forHunk: 1)?.glyph == "1")

        await scm.completeMerge()
        await scm.idle()
        #expect(scm.conflictEditor == nil && scm.snapshot.integration == .none && scm.errorMessage == nil)
        #expect(try g.git(["rev-list", "--parents", "-n", "1", "HEAD"]).split(separator: " ").count == 3)
        #expect(try String(contentsOfFile: greeting, encoding: .utf8) == "public func greeting() -> String { \"Greetings\" }\n")
        #expect(try String(contentsOfFile: colors, encoding: .utf8)
            == Self.colorsBase.replacingOccurrences(of: "white", with: "snow").replacingOccurrences(of: "orange", with: "teal"))
        #expect(!m.menuContext.hasConflicts && m.menuContext.integrationVerb.isEmpty)
    }

    @Test func cancelAsksThenAbortsTheMerge() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        let m = try await model(g)
        let scm = m.sourceControl
        let before = try g.git(["rev-parse", "HEAD"])
        scm.presentMergeAlert(branch: "feature")
        scm.cancelMergeAlert()
        await scm.idle()
        #expect(scm.mergeAlert == nil && !scm.isMerging && scm.snapshot.integration == .none)

        let editor = try await mergeFeature(scm)
        editor.choose(.theirs, forHunk: 0)
        scm.cancelMerge()
        let c = try #require(scm.confirmation)
        #expect(c.title == MergeSheetText.cancelTitle(verb: "Merge") && c.title == "Abort the merge?")
        #expect(c.message == MergeSheetText.cancelMessage(verb: "Merge") && c.choices.map(\.title) == ["Abort"])
        scm.confirmation = nil
        #expect(scm.conflictEditor != nil)
        scm.cancelMerge()
        scm.confirm(try #require(scm.confirmation).choices[0])
        await scm.idle()
        #expect(scm.conflictEditor == nil && scm.snapshot.integration == .none)
        #expect(try g.git(["rev-parse", "HEAD"]) == before)
        #expect(try g.git(["status", "--porcelain"]).isEmpty)
    }

    @Test func aRebaseAndACherryPickThroughTheSheet() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        let m = try await model(g)
        let scm = m.sourceControl

        let before = try g.git(["rev-parse", "feature"])
        scm.perform(.checkout("feature", .carry))
        scm.perform(.rebase("main"))
        await scm.idle()
        var sheet = try #require(scm.conflictEditor)
        await sheet.idle()
        #expect(sheet.state.primaryTitle == "Continue Rebase" && sheet.state.document?.theirsLabel == "feature")
        scm.cancelMerge()
        #expect(scm.confirmation?.title == "Abort the rebase?")
        scm.confirm(try #require(scm.confirmation).choices[0])
        await scm.idle()
        #expect(scm.snapshot.integration == .none && scm.conflictEditor == nil)
        #expect(try g.git(["rev-parse", "HEAD"]) == before)

        scm.perform(.rebase("main"))
        await scm.idle()
        sheet = try #require(scm.conflictEditor)
        await sheet.idle()
        await chooseEverywhere(sheet, .theirs)
        #expect(sheet.state.canMerge)
        await scm.completeMerge()
        await scm.idle()
        #expect(scm.snapshot.integration == .none && scm.conflictEditor == nil && scm.errorMessage == nil)
        #expect(try g.git(["log", "-1", "--format=%s"]) == "Feature\n")
        #expect(try g.git(["rev-parse", "HEAD~1"]) == g.git(["rev-parse", "main"]))

        scm.perform(.checkout("main", .carry))
        await scm.idle()
        scm.perform(.cherryPick(before.trimmingCharacters(in: .whitespacesAndNewlines)))
        await scm.idle()
        let pick = try #require(scm.conflictEditor)
        await pick.idle()
        #expect(pick.state.primaryTitle == "Continue Cherry-Pick" && pick.state.files.count == 2 && !pick.state.canMerge)
        await chooseEverywhere(pick, .theirs)
        await scm.completeMerge()
        await scm.idle()
        #expect(scm.snapshot.integration == .none && scm.conflictEditor == nil)
        #expect(try g.git(["log", "-1", "--format=%s"]) == "Feature\n")
        #expect(try String(contentsOfFile: g.path("Sources/DemoCore/Greeting.swift"), encoding: .utf8).contains("Welcome"))
    }

    @Test func markAsResolvedAndTheRowsOpenTheSheet() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        _ = try? g.git(["merge", "feature"])
        let m = try await model(g)
        let scm = m.sourceControl
        let colors = Self.gitPath(scm, "Colors.swift"), greeting = Self.gitPath(scm, "Greeting.swift")
        #expect(scm.conflictEditor == nil)
        scm.select("change:" + greeting)
        await scm.idle()
        let editor = try #require(scm.conflictEditor)
        await editor.idle()
        #expect(editor.state.currentFile == greeting && editor.state.primaryTitle == "Merge")
        #expect(await editor.markResolved() == false)
        editor.selectHunk(0)
        editor.beginEditing()
        editor.editedText = "<<<<<<< a\nx\n=======\ny\n>>>>>>> b\n"
        #expect(await editor.markResolved() == false)
        #expect(editor.state.lastError == "The file still has conflict markers.")
        editor.state.lastError = nil
        editor.editedText = "public func greeting() -> String { \"Greetings\" }\n"
        #expect(await editor.markResolved())
        await scm.idle()
        #expect(editor.state.files == [colors] && editor.state.currentFile == colors)
        scm.hidePane()
        #expect(scm.conflictEditor === editor)
        m.perform(.scmResolveConflicts)
        await scm.idle()
        #expect(scm.conflictEditor === editor)
        await chooseEverywhere(editor, .ours)
        m.perform(.scmMarkResolved)
        for _ in 0..<50 where !editor.state.files.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await scm.idle()
        }
        #expect(editor.state.files.isEmpty && editor.state.canMerge && editor.state.primaryTitle == "Merge")
        await scm.completeMerge()
        await scm.idle()
        #expect(scm.conflictEditor == nil && scm.snapshot.integration == .none)
        #expect(try g.git(["rev-list", "--parents", "-n", "1", "HEAD"]).split(separator: " ").count == 3)
        #expect(try String(contentsOfFile: colors, encoding: .utf8)
            == Self.colorsBase.replacingOccurrences(of: "white", with: "snow").replacingOccurrences(of: "orange", with: "purple"))
        #expect(try g.git(["log", "-1", "--format=%s"]).hasPrefix("Merge"))
    }

    @Test func showingTheShownFileKeepsItsChoices() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        let m = try await model(g)
        let editor = try await mergeFeature(m.sourceControl)
        let shown = try #require(editor.state.currentFile)
        editor.choose(.theirs, forHunk: 0)
        await editor.show(file: shown)
        #expect(editor.state.document != nil && editor.state.token(forHunk: 0)?.glyph == "1")
        m.sourceControl.cancelMerge()
        m.sourceControl.confirm(try #require(m.sourceControl.confirmation).choices[0])
        await m.sourceControl.idle()
    }

    @Test func integrateMergeAndTheReferencesBranchItems() async throws {
        let g = try conflictingPackage()
        defer { g.remove() }
        try g.git(["remote", "add", "origin", "git@example.com:owner/demo.git"])
        try g.write("Notes.txt", "stashed\n")
        try g.git(["add", "Notes.txt"])
        try g.git(["stash", "-q"])
        let m = try await model(g)
        let scm = m.sourceControl
        #expect(ShellCommand.scmMerge.isSourceControl && ShellCommand.scmMerge.title(in: m.menuContext) == "Merge…")
        #expect(ShellCommand.scmMerge.menu == "Integrate" && m.isEnabled(.scmMerge))
        scm.select("branch:feature")
        m.perform(.scmMerge)
        var alert = try #require(scm.mergeAlert)
        #expect(alert.branch == "feature" && alert.choices == ["feature"] && alert.hasChooser)
        #expect(alert.frame(window: (1400, 880)).height == MergeSheetMetrics.alertHeight + MergeSheetMetrics.alertChooserHeight)
        scm.chooseMergeBranch("nonexistent")
        alert = try #require(scm.mergeAlert)
        #expect(alert.branch == "feature")
        scm.cancelMergeAlert()

        var opened: [URL] = []
        scm.openExternally = { opened.append($0) }
        let items = scm.menu(for: "branch:feature")
        #expect(items.first { $0.title == "View on Host…" }?.isEnabled == true)
        scm.choose(.viewOnHost(branch: "feature"))
        #expect(opened == [URL(string: "https://example.com/owner/demo/tree/feature")!])
        scm.choose(.mergeInto("feature"))
        scm.choose(.newHostedRemote)
        #expect(scm.mergeAlert == nil && scm.prompt == nil && scm.confirmation == nil)

        #expect(items.first { $0.title == "Export Stashed Changes as Patch File…" }?.isEnabled == true)
        scm.choose(.exportStash("stash@{0}"))
        var p = try #require(scm.prompt)
        #expect(p.purpose == .exportStash("stash@{0}") && p.fields[0].text.hasSuffix("stash.patch"))
        let out = g.url.deletingLastPathComponent().appendingPathComponent("exported.patch").path
        p.fields[0].text = out
        scm.prompt = p
        scm.confirmPrompt()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: out) { try? await Task.sleep(nanoseconds: 20_000_000) }
        #expect(try String(contentsOfFile: out, encoding: .utf8).contains("stashed"))

        try g.git(["branch", "-D", "feature"])
        scm.refresh()
        await scm.idle()
        #expect(!m.isEnabled(.scmMerge))
    }
}
