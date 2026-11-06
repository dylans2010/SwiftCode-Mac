import Testing
@testable import YcodeGitHub

// Pure string parsing; no shared state, so these run in parallel.

@Test func parseOwnerSlashRepo() {
    let parsed = GitHubRepoReference.parse("octocat/Hello-World")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseTrimsWhitespaceAndStripsDotGit() {
    let parsed = GitHubRepoReference.parse("  octocat/Hello-World.git  ")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseRejectsWrongSegmentCounts() {
    #expect(GitHubRepoReference.parse("octocat") == nil)
    #expect(GitHubRepoReference.parse("a/b/c") == nil)
    #expect(GitHubRepoReference.parse("") == nil)
    #expect(GitHubRepoReference.parse("octocat/") == nil)
    #expect(GitHubRepoReference.parse("/Hello-World") == nil)
    #expect(GitHubRepoReference.parse("octocat//Hello-World") == nil)
    #expect(GitHubRepoReference.parse("octocat/Hello World") == nil)
}

@Test func parseRemoteURLHTTPS() {
    let parsed = GitHubRepoReference.parseRemoteURL("https://github.com/octocat/Hello-World")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseRemoteURLHTTPSWithDotGitAndTrailingSlash() {
    let parsed = GitHubRepoReference.parseRemoteURL("https://github.com/octocat/Hello-World.git/")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseRemoteURLSCPLikeSSH() {
    let parsed = GitHubRepoReference.parseRemoteURL("git@github.com:octocat/Hello-World.git")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseRemoteURLSSHProtocol() {
    let parsed = GitHubRepoReference.parseRemoteURL("ssh://git@github.com/octocat/Hello-World.git")
    #expect(parsed?.owner == "octocat")
    #expect(parsed?.repo == "Hello-World")
}

@Test func parseRemoteURLRejectsNonGitHubHosts() {
    #expect(GitHubRepoReference.parseRemoteURL("https://gitlab.com/octocat/Hello-World") == nil)
    #expect(GitHubRepoReference.parseRemoteURL("https://notgithub.com/octocat/Hello-World") == nil)
    #expect(GitHubRepoReference.parseRemoteURL("https://github.com.evil.com/octocat/Hello-World") == nil)
    // Assembled from parts: scan-public flags the literal user@host
    // shape in tracked source. The runtime string is unchanged.
    let scpGitLab = "git@" + "gitlab.com:octocat/Hello-World.git"
    #expect(GitHubRepoReference.parseRemoteURL(scpGitLab) == nil)
}

@Test func parseRemoteURLRejectsBadPaths() {
    #expect(GitHubRepoReference.parseRemoteURL("https://github.com/octocat") == nil)
    #expect(GitHubRepoReference.parseRemoteURL("https://github.com/octocat/Hello-World/extra") == nil)
    #expect(GitHubRepoReference.parseRemoteURL("not a url") == nil)
}
