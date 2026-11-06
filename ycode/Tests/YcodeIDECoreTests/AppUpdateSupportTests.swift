import Foundation
import Testing
@testable import YcodeIDECore

/// The pure update-support logic (ported from Legacy's in-app
/// `AppUpdateSupportTests.runAll()` checks, as real Swift Testing tests).
/// Only the Sparkle-free logic is covered here — feed configuration,
/// release-notes parsing, and the Remind Me Later gate — never Sparkle,
/// the network, or installation.
@Suite struct AppUpdateSupportTests {
    @Test func feedURLIsHTTPSAndPointsAtSwiftCodeMacReleases() {
        #expect(AppUpdateConfiguration.feedURLString.hasPrefix("https://"))
        #expect(AppUpdateConfiguration.feedURLString.contains("dylans2010/SwiftCode-Mac/releases/latest/download/appcast.xml"))
        #expect(AppUpdateConfiguration.feedURL != nil)
    }

    @Test func intervalsAreOneDayAndSevenDays() {
        #expect(AppUpdateConfiguration.checkInterval == 86_400)
        #expect(AppUpdateConfiguration.remindLaterInterval == 7 * 86_400)
    }

    @Test func releaseNotesHTMLBecomesPlainText() {
        let html = "<h2>New in 1.2</h2><ul><li>Faster builds</li><li>Fixed a crash &amp; a leak</li></ul><p>Thanks!</p>"
        let plain = ReleaseNotesFormatter.plainText(from: html)
        #expect(plain.contains("# New in 1.2"))
        #expect(plain.contains("• Faster builds"))
        #expect(plain.contains("crash & a leak"))
        #expect(!plain.contains("<"))
    }

    @Test func releaseNotesSplitIntoBlocks() {
        let html = "<h2>New in 1.2</h2><ul><li>Faster builds</li><li>Fixed a crash &amp; a leak</li></ul><p>Thanks!</p>"
        let blocks = ReleaseNotesFormatter.blocks(from: ReleaseNotesFormatter.plainText(from: html))
        #expect(blocks.contains(.heading("New in 1.2")))
        #expect(blocks.contains(.bullet("Faster builds")))
        #expect(blocks.contains(.body("Thanks!")))
        #expect(ReleaseNotesFormatter.blocks(fromFeedText: nil).isEmpty)
        #expect(ReleaseNotesFormatter.blocks(fromFeedText: "   ").isEmpty)
        #expect(ReleaseNotesFormatter.blocks(from: "- one\n- two").contains(.bullet("one")))
    }

    @Test func remindLaterGateSuppressesOnlyDeferredScheduledChecks() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let future: [String: TimeInterval] = ["2": 1_000_000 + 3_600]
        let past: [String: TimeInterval] = ["2": 1_000_000 - 3_600]
        #expect(RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: future, now: now, userInitiated: false))
        #expect(!RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: future, now: now, userInitiated: true))
        #expect(!RemindLaterGate.shouldSuppressOffer(version: "2", remindUntil: past, now: now, userInitiated: false))
        #expect(!RemindLaterGate.shouldSuppressOffer(version: "3", remindUntil: future, now: now, userInitiated: false))
        #expect(RemindLaterGate.remindUntil(from: now) == 1_000_000 + 7 * 86_400)
    }
}
