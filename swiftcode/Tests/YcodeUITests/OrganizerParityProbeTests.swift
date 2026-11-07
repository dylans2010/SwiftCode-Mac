import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeUI

@MainActor
@Suite(.serialized) struct OrganizerParityProbeTests {
    nonisolated static let outDir = ProcessInfo.processInfo.environment["SWIFTCODE_ORGANIZER_SHOTS"]
    nonisolated static let archives = ProcessInfo.processInfo.environment["SWIFTCODE_ORGANIZER_ARCHIVES"]

    @Test(.enabled(if: outDir != nil && archives != nil)) func pairedStates() throws {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: try #require(Self.outDir))
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for appearance in ["light", "dark"] {
            let org = OrganizerController(archivesDirectory: URL(fileURLWithPath: try #require(Self.archives)))
            let win = NSWindow(contentViewController: org)
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            win.title = "Organizer"
            org.installToolbar()
            org.reload()
            let all = org.groups.flatMap(\.archives)
            if let newest = all.filter(\.hasApplication).max(by: { ($0.created ?? .distantPast) < ($1.created ?? .distantPast) }) {
                org.select(archiveAt: newest.url)
            }
            org.showPage("Archives", section: "Products")
            try shot(win, "mac-organizer-\(appearance)-archives", out)
            print("organizer details: \(org.detailRows.map { "\($0.0)=\($0.1)" })")
            org.showPage("Overview", section: "Insights")
            try shot(win, "mac-organizer-\(appearance)-overview", out)
            win.close()
        }
    }

    func shot(_ win: NSWindow, _ name: String, _ out: URL) throws {
        win.contentView?.layoutSubtreeIfNeeded()
        try LinuxParityProbeTests.write(window: win, name: name, to: out)
    }
}
