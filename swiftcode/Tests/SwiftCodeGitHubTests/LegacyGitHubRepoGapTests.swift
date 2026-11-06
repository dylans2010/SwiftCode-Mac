import Foundation
import Testing
@testable import SwiftCodeGitHub

// MARK: - Legacy GitHub repo reference gap tests (Wave 18)
//
// Ported from Legacy
// `SwiftCode/Backend/Assist/AssistDocsGitHubToolsTestSuite.swift`
// (`testRepoURLResolution` / `testValidateOwnerRepo`, Dylan's own code;
// direct port authorised under MIT), adapted to the SwiftCode shape:
// `GitHubRepoReference.parse` / `parseRemoteURL`.
//
// The rest of that suite is already covered: `fetch_documentation`
// registration, candidate resolution, DocC JSON parsing, HTML parsing,
// and the Apple URL guard live in `SwiftCodeEnginesToolsTests`, and the
// `github_repo` tool operations (including binary-by-extension) live in
// `SwiftCodeGitToolsTests` plus `GitHubRepoReferenceTests`.
//
// Deliberately NOT ported from the same Legacy tests:
//   - the `/tree/main/...` URL case: Legacy accepted it, SwiftCode's
//     `parseRemoteURL` rejects extra path segments by design, so
//     asserting acceptance would contradict SwiftCode's stricter rule.
//   - the invalid-character rejection half of owner/repo validation:
//     SwiftCode's `parse` is intentionally lenient on character sets
//     (it rejects only whitespace/empty segments), so only the
//     valid-characters acceptance half is portable here.
//   - the NUL-byte half of binary classification: SwiftCode classifies
//     `get_file` results by extension only, without fetching.
//
// No Swift toolchain exists in this environment, so these tests have
// NOT been compiled or run — statically verified only. On Dylan's Mac:
// run with `swift test --filter LegacyGitHubRepoGapTests`.

@Test func parseAcceptsValidOwnerRepoCharacters() {
    // Legacy's valid-character cases: underscores, dots, and dashes
    // in both segments must parse.
    #expect(GitHubRepoReference.parse("org_1.2/r-e_p.o")?.owner == "org_1.2")
    #expect(GitHubRepoReference.parse("org_1.2/r-e_p.o")?.repo == "r-e_p.o")
    #expect(GitHubRepoReference.parse("dylans2010/SwiftCode-Mac")?.owner == "dylans2010")
    #expect(GitHubRepoReference.parse("dylans2010/SwiftCode-Mac")?.repo == "SwiftCode-Mac")
}
