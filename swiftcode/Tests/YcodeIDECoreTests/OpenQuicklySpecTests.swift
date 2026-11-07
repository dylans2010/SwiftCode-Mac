import Foundation
import Testing
@testable import YcodeIDECore

@Suite struct OpenQuicklySpecTests {
    @Test func scoreValues() {
        #expect(FuzzyMatch.score("a", "ab") == 88)
        #expect(FuzzyMatch.score("b", "a_b") == 67)
        #expect(FuzzyMatch.score("b", "aB") == 58)
        #expect(FuzzyMatch.score("A B", "ab") == FuzzyMatch.score("ab", "ab"))
        #expect(FuzzyMatch.score("ba", "ab") == nil)
        #expect(FuzzyMatch.score("abc", "xyz") == nil)
    }

    @Test func limitAndTiesFilesFirst() {
        let sym = FuzzyMatch.Candidate(title: "View", detail: "a.swift", path: "/a.swift", line: 3, kind: .symbol)
        let file = FuzzyMatch.Candidate(title: "View", detail: "/", path: "/View", kind: .file)
        #expect(FuzzyMatch.search("view", in: [sym, file]).first?.kind == .file)
        let many = (0..<30).map { FuzzyMatch.Candidate(title: "v\($0)", detail: "", path: "/v\($0)", kind: .file) }
        #expect(FuzzyMatch.search("v", in: many).count == 20)
    }
}
