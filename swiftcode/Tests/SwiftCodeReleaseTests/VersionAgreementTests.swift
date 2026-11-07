import Foundation
import Testing
import SwiftCodeRelease

@Suite struct VersionAgreementTests {
    private static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let root = package.deletingLastPathComponent()

    private static func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private static func versionFile() throws -> String {
        try text(package.appendingPathComponent("VERSION")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func theConstantMatchesTheVersionFile() throws {
        #expect(SwiftCodeRelease.version == (try Self.versionFile()))
    }

    @Test func theVersionFileIsOneSemanticVersionLine() throws {
        let raw = try Self.text(Self.package.appendingPathComponent("VERSION"))
        #expect(raw.filter { $0 == "\n" }.count == 1)
        #expect(try Self.versionFile().wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?/) != nil)
    }

    @Test func theMetainfoNamesThisVersionAsItsNewestRelease() throws {
        let metainfo = Self.root.appendingPathComponent("packaging/flatpak/io.github.MarcoDotIO.Ycode.metainfo.xml")
        guard FileManager.default.fileExists(atPath: metainfo.path) else { return }
        let first = try Self.text(metainfo).firstMatch(of: /<release[^>]*version="([^"]+)"/)
        #expect(first.map { String($0.output.1) } == (try Self.versionFile()))
    }

    @Test func thePackagingScriptsStateNoVersionOfTheirOwn() throws {
        let scripts = ["swiftcode/scripts/make-app.sh", "swiftcode/scripts/make-dmg.sh", "packaging/macos/Info.plist.in",
                       "packaging/flatpak/build-flatpak.sh", "packaging/flatpak/io.github.MarcoDotIO.Ycode.yml"]
        let version = try Self.versionFile()
        for s in scripts {
            let url = Self.root.appendingPathComponent(s)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            #expect(try !Self.text(url).contains(version), "\(s) states the version; read swiftcode/VERSION instead")
        }
    }

    @Test func theVersionLineNamesTheTool() {
        #expect(SwiftCodeRelease.versionLine(tool: "swiftcodebuild") == "swiftcodebuild \(SwiftCodeRelease.version)")
    }
}

@Suite struct BundledHelpersTests {
    @Test func theHelpersFolderComesFirstOnThePath() {
        let exe = URL(fileURLWithPath: "/Apps/SwiftCode.app/Contents/MacOS/SwiftCode")
        let path = SwiftCodeRelease.pathWithBundledHelpers(executable: exe, path: "/usr/bin") { $0 == "/Apps/SwiftCode.app/Contents/Helpers" }
        #expect(path == "/Apps/SwiftCode.app/Contents/Helpers:/usr/bin")
    }

    @Test func aBundleWithoutHelpersLeavesThePathAlone() {
        let exe = URL(fileURLWithPath: "/x/.build/debug/SwiftCodeApp")
        #expect(SwiftCodeRelease.pathWithBundledHelpers(executable: exe, path: "/usr/bin") { _ in false } == nil)
    }

    @Test func aLinuxPackagePutsItsToolsFirstWhereverItIsUnpacked() {
        let exe = URL(fileURLWithPath: "/anywhere/Y/bin/swiftcode-ide")
        let inFlatpak = SwiftCodeRelease.packageEnvironment(executable: exe, environment: ["PATH": "/usr/bin", "FLATPAK_ID": "x"]) { $0 == "/anywhere/Y/libexec/swiftcode-host" }
        #expect(inFlatpak["PATH"] == "/anywhere/Y/libexec/swiftcode-host:/anywhere/Y/bin:/usr/bin")
        #expect(inFlatpak["SWIFTCODE_SWB"] == "/anywhere/Y/bin/swiftcode-swb")
        let plain = SwiftCodeRelease.packageEnvironment(executable: exe, environment: ["PATH": "/usr/bin"]) { $0 == "/anywhere/Y/libexec/swiftcode-host" }
        #expect(plain["PATH"] == "/anywhere/Y/bin:/usr/bin")
    }

    @Test func aBuildFolderIsNotAPackage() {
        let exe = URL(fileURLWithPath: "/x/.build/release/swiftcode-ide")
        #expect(SwiftCodeRelease.packageEnvironment(executable: exe, environment: ["PATH": "/usr/bin"]) { _ in false }.isEmpty)
    }

    @Test func noPathStillFindsTheSystem() {
        let exe = URL(fileURLWithPath: "/A.app/Contents/MacOS/Y")
        #expect(SwiftCodeRelease.pathWithBundledHelpers(executable: exe, path: nil) { _ in true }?.hasSuffix(":/usr/bin:/bin:/usr/sbin:/sbin") == true)
    }
}
