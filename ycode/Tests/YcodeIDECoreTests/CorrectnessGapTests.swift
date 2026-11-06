import Foundation
import Testing
@testable import YcodeIDECore

/// Correctness gap closure: the real Myers diff engine
/// (`MyersDiff`) and the `safe_undo` journal (`SafeUndoJournal`).
/// Pure / local-disk behaviour only; no network, no credentials.
///
/// Diff vectors mirror Legacy's `AssistDiffEngine` expectations
/// (unified format, 3 context lines, `@@ -a,b +c,d @@` headers):
/// empty/empty, identical, pure insert, pure delete, interleaved,
/// and a large file with one middle insertion (the case the old
/// positional diff got wrong — the whole tail read as changed).
@Suite struct CorrectnessGapDiffTests {
    @Test func emptyAgainstEmpty() {
        let r = MyersDiff.diff(old: [], new: [])
        #expect(r.operations.isEmpty && r.added == 0 && r.removed == 0 && !r.usedFallback)
        #expect(MyersDiff.unifiedDiff(old: "", new: "", file: "a.txt") == "--- a/a.txt\n+++ b/a.txt")
        #expect(MyersDiff.editDistance(old: [], new: []) == 0)
    }

    @Test func identical() {
        let lines = ["one", "two", "three"]
        let r = MyersDiff.diff(old: lines, new: lines)
        #expect(r.added == 0 && r.removed == 0 && !r.usedFallback)
        #expect(r.operations == lines.map(MyersDiff.Operation.equal))
        let text = MyersDiff.unifiedDiff(old: lines.joined(separator: "\n"), new: lines.joined(separator: "\n"), file: "a.txt")
        #expect(text == "--- a/a.txt\n+++ b/a.txt")
        #expect(MyersDiff.editDistance(old: lines, new: lines) == 0)
    }

    @Test func pureInsert() {
        let r = MyersDiff.diff(old: ["a", "b"], new: ["a", "x", "b"])
        #expect(r.added == 1 && r.removed == 0 && !r.usedFallback)
        #expect(r.operations == [.equal("a"), .insert("x"), .equal("b")])
        let text = MyersDiff.unifiedDiff(old: "a\nb", new: "a\nx\nb", file: "a.txt")
        #expect(text.contains("@@ -1,2 +1,3 @@"))
        #expect(text.contains("+x"))
        #expect(!text.contains("-a") && !text.contains("-b"))
    }

    @Test func pureDelete() {
        let r = MyersDiff.diff(old: ["a", "x", "b"], new: ["a", "b"])
        #expect(r.added == 0 && r.removed == 1 && !r.usedFallback)
        #expect(r.operations == [.equal("a"), .delete("x"), .equal("b")])
        #expect(MyersDiff.editDistance(old: ["a", "x", "b"], new: ["a", "b"]) == 1)
    }

    @Test func interleaved() {
        let r = MyersDiff.diff(old: ["a", "b", "c", "d"], new: ["a", "x", "c", "y"])
        #expect(r.added == 2 && r.removed == 2 && !r.usedFallback)
        #expect(r.operations == [.equal("a"), .delete("b"), .insert("x"), .equal("c"), .delete("d"), .insert("y")])
        #expect(MyersDiff.editDistance(old: ["a", "b", "c", "d"], new: ["a", "x", "c", "y"]) == 4)
    }

    @Test func middleInsertionLeavesTailEqual() {
        // The old positional diff reported the whole tail as
        // changed here (5 deletions + 5 insertions); Myers reports
        // exactly one insertion.
        let old = ["a", "b", "c", "d", "e"]
        let new = ["a", "NEW", "b", "c", "d", "e"]
        let r = MyersDiff.diff(old: old, new: new)
        #expect(r.added == 1 && r.removed == 0 && !r.usedFallback)
        let text = MyersDiff.unifiedDiff(old: old.joined(separator: "\n"), new: new.joined(separator: "\n"), file: "a.txt")
        #expect(text.contains("+NEW"))
        #expect(!text.contains("-b") && !text.contains("-e"))
        #expect(text.contains(" a") && text.contains(" e"))
    }

    @Test func largeFileSingleInsertion() {
        let old = (0..<2000).map { "line \($0)" }
        var new = old
        new.insert("INSERTED", at: 1000)
        let r = MyersDiff.diff(old: old, new: new)
        #expect(r.added == 1 && r.removed == 0 && !r.usedFallback)
        let text = MyersDiff.unifiedDiff(old: old.joined(separator: "\n"), new: new.joined(separator: "\n"), file: "big.txt")
        #expect(text.contains("+INSERTED"))
        // One hunk only (3 context lines each side), not the file.
        #expect(text.components(separatedBy: "@@").count == 3)
    }

    @Test func farApartChangesSplitIntoHunks() {
        let old = (0..<30).map { "line \($0)" }
        var new = old
        new[2] = "CHANGED-2"
        new[27] = "CHANGED-27"
        let text = MyersDiff.unifiedDiff(old: old.joined(separator: "\n"), new: new.joined(separator: "\n"), file: "a.txt")
        #expect(text.contains("-line 2") && text.contains("+CHANGED-2"))
        #expect(text.contains("-line 27") && text.contains("+CHANGED-27"))
        #expect(text.components(separatedBy: "@@").count == 5) // two hunk headers
    }

    @Test func hugeEditDistanceFallsBackHonestly() {
        let old = (0..<3000).map { "old \($0)" }
        let new = (0..<3000).map { "new \($0)" }
        let r = MyersDiff.diff(old: old, new: new)
        #expect(r.usedFallback)
        #expect(r.added == 3000 && r.removed == 3000)
        #expect(MyersDiff.editDistance(old: old, new: new) == nil)
    }

    @Test func emptyFileLines() {
        #expect(MyersDiff.lines(of: "") == [])
        #expect(MyersDiff.lines(of: "x\n") == ["x", ""])
    }
}

@Suite struct CorrectnessGapUndoJournalTests {
    func journal() throws -> (SafeUndoJournal, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ycode-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return (SafeUndoJournal(baseDirectory: base), base)
    }

    func workspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ycode-undo-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func recordAndPopRoundTrip() throws {
        let (j, _) = try journal()
        let ws = try workspace()
        j.record(workspaceRoot: ws, relativePath: "a.txt", original: "v1\n", tool: "file_write")
        #expect(j.entries(workspaceRoot: ws).count == 1)
        #expect(j.entries(workspaceRoot: ws).first?.original == "v1\n")
        let popped = j.popLast(workspaceRoot: ws)
        #expect(popped?.relativePath == "a.txt" && popped?.original == "v1\n" && popped?.tool == "file_write")
        #expect(j.entries(workspaceRoot: ws).isEmpty)
        #expect(j.popLast(workspaceRoot: ws) == nil)
    }

    @Test func nilOriginalMeansFileDidNotExist() throws {
        let (j, _) = try journal()
        let ws = try workspace()
        j.record(workspaceRoot: ws, relativePath: "new.txt", original: nil, tool: "file_create")
        #expect(j.popLast(workspaceRoot: ws)?.original == nil)
    }

    @Test func unrecordedEntrySurvives() throws {
        let (j, _) = try journal()
        let ws = try workspace()
        j.record(workspaceRoot: ws, relativePath: "big.bin", original: nil, unrecorded: true, tool: "file_write")
        let popped = j.popLast(workspaceRoot: ws)
        #expect(popped?.unrecorded == true)
    }

    @Test func entriesAreCappedOldestFirst() throws {
        let (j, _) = try journal()
        let ws = try workspace()
        for i in 0..<105 { j.record(workspaceRoot: ws, relativePath: "f\(i).txt", original: "\(i)", tool: "file_write") }
        let entries = j.entries(workspaceRoot: ws)
        #expect(entries.count == SafeUndoJournal.maxEntries)
        #expect(entries.first?.relativePath == "f5.txt")
        #expect(entries.last?.relativePath == "f104.txt")
    }

    @Test func workspacesAreIsolated() throws {
        let (j, _) = try journal()
        let a = try workspace()
        let b = try workspace()
        j.record(workspaceRoot: a, relativePath: "a.txt", original: "A", tool: "file_write")
        #expect(j.entries(workspaceRoot: b).isEmpty)
        #expect(j.popLast(workspaceRoot: b) == nil)
        #expect(j.entries(workspaceRoot: a).count == 1)
    }

    @Test func journalPersistsAcrossInstances() throws {
        let (j, base) = try journal()
        let ws = try workspace()
        j.record(workspaceRoot: ws, relativePath: "a.txt", original: "v1", tool: "file_write")
        let reopened = SafeUndoJournal(baseDirectory: base)
        #expect(reopened.entries(workspaceRoot: ws).count == 1)
        #expect(reopened.popLast(workspaceRoot: ws)?.original == "v1")
    }

    @Test func clearDropsJournal() throws {
        let (j, _) = try journal()
        let ws = try workspace()
        j.record(workspaceRoot: ws, relativePath: "a.txt", original: "v1", tool: "file_write")
        j.clear(workspaceRoot: ws)
        #expect(j.entries(workspaceRoot: ws).isEmpty)
    }
}
