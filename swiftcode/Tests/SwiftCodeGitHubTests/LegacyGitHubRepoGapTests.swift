import Foundation
import Testing
@testable import SwiftCodeGitHub

@Test func parseAcceptsValidOwnerRepoCharacters() {
    #expect(GitHubRepoReference.parse("org_1.2/r-e_p.o")?.owner == "org_1.2")
    #expect(GitHubRepoReference.parse("org_1.2/r-e_p.o")?.repo == "r-e_p.o")
    #expect(GitHubRepoReference.parse("dylans2010/SwiftCode-Mac")?.owner == "dylans2010")
    #expect(GitHubRepoReference.parse("dylans2010/SwiftCode-Mac")?.repo == "SwiftCode-Mac")
}
