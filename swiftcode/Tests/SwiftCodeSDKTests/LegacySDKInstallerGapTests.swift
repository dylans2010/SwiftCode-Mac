import XCTest
@testable import SwiftCodeSDK

final class LegacySDKInstallerGapTests: XCTestCase {

    private func makePrefix() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sdk-installer-gap-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func packageDir(at prefix: URL) throws -> URL {
        let dir = prefix
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("@swiftcode", isDirectory: true)
            .appendingPathComponent("sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writePackageJSON(at prefix: URL, json: [String: Any]) throws {
        let dir = try packageDir(at: prefix)
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: dir.appendingPathComponent("package.json"))
    }

    private func writeEntries(at prefix: URL) throws {
        let dir = try packageDir(at: prefix)
        for entry in ["dist/index.js", "dist/index.d.ts", "dist/assist.js", "dist/assistUI.js"] {
            let url = dir.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("// stub".utf8).write(to: url)
        }
    }

    private func writeFakeNPM(named name: String, in dir: URL, body: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private var successScript: String {
        """
        #!/bin/sh
        PREFIX="$4"
        mkdir -p "$PREFIX/node_modules/@swiftcode/sdk/dist"
        printf '%s' '{"name":"@swiftcode/sdk","version":"1.0.0"}' > "$PREFIX/node_modules/@swiftcode/sdk/package.json"
        for f in index.js index.d.ts assist.js assistUI.js; do
          printf '%s' '// stub' > "$PREFIX/node_modules/@swiftcode/sdk/dist/$f"
        done
        echo "fake npm: installed @swiftcode/sdk@1.0.0"
        exit 0
        """
    }

    private var failureScript: String {
        """
        #!/bin/sh
        PREFIX="$4"
        mkdir -p "$PREFIX/node_modules/@swiftcode/sdk/dist"
        printf '%s' '{"name":"@swiftcode/sdk","version":"1.0.0"}' > "$PREFIX/node_modules/@swiftcode/sdk/package.json"
        for f in index.js index.d.ts assist.js assistUI.js; do
          printf '%s' '// stub' > "$PREFIX/node_modules/@swiftcode/sdk/dist/$f"
        done
        echo "npm ERR! fake registry failure: connection refused" >&2
        exit 1
        """
    }

    private var noOpScript: String {
        """
        #!/bin/sh
        echo "fake npm: nothing installed"
        exit 0
        """
    }

    private func options(prefix: URL, npm: URL, reachable: Bool, fallback: URL?) -> SDKInstaller.InstallOptions {
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.npmExecutable = npm
        options.reachabilityProbe = { _ in reachable }
        options.bundledFallbackURL = fallback
        options.timeout = 60
        return options
    }

    func testInspectCorruptWhenVersionMissing() throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        try writePackageJSON(at: prefix, json: ["name": "@swiftcode/sdk"])
        try writeEntries(at: prefix)
        let inspection = SDKInstaller.inspect(prefix: prefix)
        guard case .corrupt(let reason) = inspection else {
            return XCTFail("Expected .corrupt for a missing version, got \(inspection)")
        }
        XCTAssertTrue(reason.contains("version"), reason)
    }

    func testInspectCorruptWhenNameMissing() throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        try writePackageJSON(at: prefix, json: ["version": "1.0.0"])
        try writeEntries(at: prefix)
        let inspection = SDKInstaller.inspect(prefix: prefix)
        guard case .corrupt(let reason) = inspection else {
            return XCTFail("Expected .corrupt for a missing name, got \(inspection)")
        }
        XCTAssertTrue(reason.contains("@swiftcode/sdk"), reason)
    }

    func testInstallSucceedsWithStubNpmAfterVerification() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-success", in: prefix, body: successScript)
        let noFallback = prefix.appendingPathComponent("does-not-exist.tgz")
        let result = await SDKInstaller.install(
            options: options(prefix: prefix, npm: npm, reachable: true, fallback: noFallback))
        XCTAssertTrue(result.success, result.message)
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.message.contains("GitHub"))
    }

    func testInstallFailsWhenStubNpmSucceedsButVerificationFails() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-noop", in: prefix, body: noOpScript)
        let noFallback = prefix.appendingPathComponent("does-not-exist.tgz")
        let result = await SDKInstaller.install(
            options: options(prefix: prefix, npm: npm, reachable: true, fallback: noFallback))
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.message.contains("still missing"), result.message)
    }

    func testFailedNpmCannotReportSuccessEvenIfItWroteFiles() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-fails", in: prefix, body: failureScript)
        let noFallback = prefix.appendingPathComponent("does-not-exist.tgz")
        let result = await SDKInstaller.install(
            options: options(prefix: prefix, npm: npm, reachable: true, fallback: noFallback))
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.message.contains("exited with code 1"), result.message)
        XCTAssertTrue(result.log.joined(separator: "\n").contains("fake registry failure"),
                      result.log.joined(separator: "\n"))
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .ok(version: "1.0.0"))
    }

    func testInstallFallsBackWhenGitHubUnreachable() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-success", in: prefix, body: successScript)
        let fallbackDir = prefix.appendingPathComponent("bundled-fallback", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true)
        let result = await SDKInstaller.install(
            options: options(prefix: prefix, npm: npm, reachable: false, fallback: fallbackDir))
        XCTAssertTrue(result.success, result.message)
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertTrue(result.usedFallback)
        XCTAssertTrue(result.message.contains("bundled"), result.message)
    }
}
