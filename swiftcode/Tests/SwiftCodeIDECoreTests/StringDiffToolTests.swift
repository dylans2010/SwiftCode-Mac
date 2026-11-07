import Foundation
import Testing
@testable import SwiftCodeIDECore

@Suite struct StringDiffToolTests {
    @Test func changedLinesShowAsMinusPlusWithHeaders() {
        let diff = StringDiffTool.simpleDiff(old: "one\ntwo\nthree\n", new: "one\nTWO\nthree\n", file: "a.txt")
        #expect(diff.contains("--- a/a.txt"))
        #expect(diff.contains("+++ b/a.txt"))
        #expect(diff.contains("-two"))
        #expect(diff.contains("+TWO"))
        #expect(diff.contains(" one"))
        #expect(diff.contains("@@"))
    }

    @Test func identicalInputsRenderOnlyHeaders() {
        let diff = StringDiffTool.simpleDiff(old: "same\n", new: "same\n", file: "a.txt")
        #expect(diff.contains("--- a/a.txt"))
        #expect(diff.contains("+++ b/a.txt"))
        #expect(!diff.contains("@@"))
    }

    @Test func addedAndRemovedLinesAreMarked() {
        let diff = StringDiffTool.simpleDiff(old: "keep\nremove\n", new: "keep\nadd\n", file: "b.txt")
        #expect(diff.contains("-remove"))
        #expect(diff.contains("+add"))
        #expect(diff.contains(" keep"))
    }
}

@Suite struct DocumentationAnalyzerTests {
    @Test func fourSectionsAreParsed() {
        let reply = """
        # Overview
        This API draws windows.
        # Integration Opportunities
        Use it in the editor.
        # Suggested Code Implementation
        ```swift
        let w = Window()
        ```
        # Potential Improvements
        Cache the layout.
        """
        let results = DocumentationAnalyzer.parseAIResponse(reply)
        #expect(results.overview.contains("draws windows"))
        #expect(results.integrationOpportunities.contains("editor"))
        #expect(results.suggestedCode.contains("let w = Window()"))
        #expect(results.potentialImprovements.contains("Cache the layout"))
    }

    @Test func missingSectionsFallBackToPlaceholders() {
        let results = DocumentationAnalyzer.parseAIResponse("Just a paragraph, no headings.")
        #expect(results.overview == "No overview provided.")
        #expect(results.integrationOpportunities == "No integration opportunities identified.")
        #expect(results.suggestedCode == "No code snippets suggested.")
        #expect(results.potentialImprovements == "No improvements suggested.")
    }
}
