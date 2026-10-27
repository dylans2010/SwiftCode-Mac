import Foundation

/// In-app self-checks for the Sparkle-free update logic, in the same style
/// as the project's other in-app test suites (for example
/// `AssistRuntimeTestSuite`).
///
/// This project has no XCTest target, so these checks are not run by CI.
/// They cover only the pure logic in `AppUpdateSupport.swift` — feed
/// configuration, release-notes parsing, and the Remind Me Later gate —
/// never Sparkle itself, network access, or installation. Run them from a
/// debug harness on a Mac with:
/// `AppUpdateSupportTests.runAll()` and inspect the returned failures
/// (an empty array means every check passed).
enum AppUpdateSupportTests {
    struct Result {
        let testName: String
        let passed: Bool
        let message: String
    }

    static func runAll() -> [Result] {
        var results: [Result] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool, _ message: String = "") {
            let passed = condition()
            results.append(Result(testName: name, passed: passed, message: passed ? "OK" : (message.isEmpty ? "Failed" : message)))
        }

        // Feed configuration
        check("feed URL is HTTPS", AppUpdateConfiguration.feedURLString.hasPrefix("https://"))
        check(
            "feed URL points at SwiftCode-Mac releases",
            AppUpdateConfiguration.feedURLString.contains("dylans2010/SwiftCode-Mac/releases/latest/download/appcast.xml")
        )
        check("feed URL parses", AppUpdateConfiguration.feedURL != nil)
        check("check interval is one day", AppUpdateConfiguration.checkInterval == 86_400)
        check("remind-later interval is seven days", AppUpdateConfiguration.remindLaterInterval == 7 * 86_400)

        // Release-notes HTML -> plain text
        let html = "<h2>New in 1.2</h2><ul><li>Faster builds</li><li>Fixed a crash &amp; a leak</li></ul><p>Thanks!</p>"
        let plain = ReleaseNotesFormatter.plainText(from: html)
        check("headings survive HTML stripping", plain.contains("# New in 1.2"), plain)
        check("list items become bullets", plain.contains("• Faster builds"), plain)
        check("entities are decoded", plain.contains("crash & a leak"), plain)
        check("no tags remain", !plain.contains("<"), plain)

        let blocks = ReleaseNotesFormatter.blocks(from: plain)
        check("heading block parsed", blocks.contains(.heading("New in 1.2")))
        check("bullet blocks parsed", blocks.contains(.bullet("Faster builds")))
        check("body block parsed", blocks.contains(.body("Thanks!")))
        check("empty notes produce no blocks", ReleaseNotesFormatter.blocks(fromFeedText: nil).isEmpty)
        check("blank notes produce no blocks", ReleaseNotesFormatter.blocks(fromFeedText: "   ").isEmpty)
        check("dash lists become bullets", ReleaseNotesFormatter.blocks(from: "- one\n- two").contains(.bullet("one")))

        // Remind Me Later gate
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future: [String: TimeInterval] = ["2": 1_000_000 + 3_600]
        let past: [String: TimeInterval] = ["2": 1_000_000 - 3_600]
        check(
            "deferred version is suppressed for scheduled checks",
            RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: future, now: now, userInitiated: false)
        )
        check(
            "deferred version is NOT suppressed for manual checks",
            !RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: future, now: now, userInitiated: true)
        )
        check(
            "expired deferral does not suppress",
            !RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: past, now: now, userInitiated: false)
        )
        check(
            "unknown version is not suppressed",
            !RemindLaterGate.shouldSuppressOffer(version: "3", remindUntil: future, now: now, userInitiated: false)
        )
        check(
            "remind-until is seven days out",
            RemindLaterGate.remindUntil(from: now) == 1_000_000 + 7 * 86_400
        )

        return results
    }
}
