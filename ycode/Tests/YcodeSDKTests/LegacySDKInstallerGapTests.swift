import XCTest
@testable import YcodeSDK

// MARK: - Legacy SDK installer gap tests (Wave 18)
//
// Ported from Legacy `SwiftCode/SDK/Host/SDKInstallerTests.swift`
// (Dylan's own code; direct port authorised under MIT), adapted to the
// Ycode shape: `SDKInstaller.inspect` / `install(options:)` with an
// injectable `npmExecutable`, so the npm half is exercised with a stub
// shell script instead of a real npm.
//
// What is ported here — the Legacy install cases `SDKInstallerTests`
// does NOT already cover:
//   - inspect: corrupt when the version field is missing, and when
//     the name field is missing (the entrypoint/wrong-package cases
//     are already `testCorruptWhenEntriesMissing` /
//     `testCorruptWhenWrongPackage`);
//   - install succeeds with a stub npm that writes a valid package
//     (success is reported only after `inspect` verifies it — the
//     core of Legacy's `testInstallSuccess`);
//   - install fails when the stub npm exits 0 but writes nothing
//     (Legacy's `testInstallFailsWhenNpmSucceedsButVerificationFails`);
//   - install fails honestly when the stub npm exits non-zero even
//     though it wrote files, and the real error text survives in the
//     log (Legacy's `testFailedNpmCannotReportSuccessEvenIfItWroteFiles`
//     + `testInstallFailureReportsRealErrorText`);
//   - install falls back to the bundled copy when GitHub is
//     unreachable (Legacy's `testInstallFallsBackWhenGitHubUnreachable`).
//
// Deliberately NOT ported:
//   - `testRealBundledTarballInstallsAndImports` and
//     `testRealRemoteDownloadOrBundledFallbackImports`: no SDK tarball
//     ships in this repo (`testBundledFallbackIsAbsentWithReason`
//     pins that) and tests must not hit the network.
//   - `testInstallIsIdempotentWhenAlreadyOK` and
//     `testInstallFailsHonestlyWhenUnreachableAndNoFallback`: already
//     `testInstallShortCircuitsWhenAlreadyOk` and
//     `testInstallFailsHonestlyWithNoSource`.
//
// No Swift toolchain exists in this environment, so these tests have
// NOT been compiled or run — statically verified only. On Dylan's Mac:
// run with `swift test --filter LegacySDKInstallerGapTests`.

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

    /// A stub npm: a shell script run as the npm binary. `install`
    /// receives `install <source> --prefix <prefix> ...`, so the
    /// prefix is `$4`. Writes `body` to `<dir>/<name>` and marks it
    /// executable.
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

    // MARK: - Inspection

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

    // MARK: - Install with a stub npm

    func testInstallSucceedsWithStubNpmAfterVerification() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-success", in: prefix, body: successScript)
        // A non-existent fallback must not trigger a retry path.
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
        // The real error text survives in the log, verbatim.
        XCTAssertTrue(result.log.joined(separator: "\n").contains("fake registry failure"),
                      result.log.joined(separator: "\n"))
        // And the files the failed npm wrote do not turn the install
        // into a success: the verification gate, not npm's exit code
        // alone, decides — but here npm itself failed, so the install
        // must fail even though a valid package is now on disk.
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .ok(version: "1.0.0"))
    }

    func testInstallFallsBackWhenGitHubUnreachable() async throws {
        let prefix = makePrefix()
        defer { try? FileManager.default.removeItem(at: prefix) }
        let npm = try writeFakeNPM(named: "npm-success", in: prefix, body: successScript)
        // The fallback must exist on disk for the installer to use it;
        // an empty directory stands in for the bundled copy here, and
        // the stub npm does the (simulated) install from it.
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
