// NOTE (2026-10-12): No Swift toolchain exists in this environment, so
// these tests have NOT been compiled or run — statically verified only.
// They also require a real XCTest test target: this project currently
// has none (the app target is the only target), so this file is
// registered in the xcodeproj as a source reference only and is NOT in
// any target's Sources build phase — `import XCTest` would not compile
// in the app target. On Dylan's Mac: create an XCTest target for the
// project, add this file to it, then run the suite with xcodebuild.

import XCTest
@testable import SwiftCode

// MARK: - SDKInstallerTests
//
// Tests for `SDKInstaller` against a stubbed home directory:
//   - inspect: missing / corrupt (no version) / versionMismatch / ok
//   - install success via a stub `npm` script (no network, no real npm)
//   - install falls back to the bundled copy when GitHub is unreachable
//   - install failure surfaces the REAL npm error text (never fake success)
//
// The stub `npm` is a small bash script written into the temp dir. It
// emulates just enough of `npm install <source> --prefix <dir>`:
//   - a source URL containing "unreachable" exits 1 with an error line
//   - otherwise it materializes node_modules/@swiftcode/sdk/package.json
//     (honoring STUB_WRITE_CORRUPT=1 to write a version-less package.json,
//     exercising the "npm exited 0 but verification failed" path)

final class SDKInstallerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDKInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var prefix: URL {
        tempDir.appendingPathComponent(".swiftcode/sdk", isDirectory: true)
    }

    private func installedPackageJSON(version: String?) throws {
        let dir = prefix
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("@swiftcode/sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var json: [String: Any] = ["name": "@swiftcode/sdk"]
        if let version { json["version"] = version }
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: dir.appendingPathComponent("package.json"))
    }

    /// Writes the stub `npm` script and returns its URL.
    private func stubNPM() throws -> URL {
        let script = tempDir.appendingPathComponent("npm-stub")
        let body = """
        #!/bin/bash
        # Stub npm for SDKInstallerTests: emulates `npm install <source> --prefix <dir>`.
        PREFIX=""
        SOURCE=""
        PREV=""
        for ARG in "$@"; do
          if [ "$PREV" = "--prefix" ]; then PREFIX="$ARG"; fi
          if [ "$PREV" = "install" ]; then SOURCE="$ARG"; fi
          PREV="$ARG"
        done
        echo "+ @swiftcode/sdk@1.0.0"
        case "$SOURCE" in
          *unreachable*)
            echo "npm ERR! network request to $SOURCE failed: getaddrinfo ENOTFOUND" >&2
            exit 1
            ;;
        esac
        TARGET="$PREFIX/node_modules/@swiftcode/sdk"
        mkdir -p "$TARGET"
        if [ -d "$SOURCE" ] && [ -f "$SOURCE/package.json" ]; then
          cp "$SOURCE/package.json" "$TARGET/package.json"
        elif [ "$STUB_WRITE_CORRUPT" = "1" ]; then
          printf '{"name":"@swiftcode/sdk"}' > "$TARGET/package.json"
        else
          printf '{"name":"@swiftcode/sdk","version":"1.0.0"}' > "$TARGET/package.json"
        fi
        exit 0
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    /// A local directory usable as the "bundled fallback" source.
    private func fallbackSource(version: String = "1.0.0") throws -> URL {
        let dir = tempDir.appendingPathComponent("fallback-sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = ["name": "@swiftcode/sdk", "version": version]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: dir.appendingPathComponent("package.json"))
        return dir
    }

    private func baseOptions() throws -> SDKInstaller.InstallOptions {
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.npmExecutable = try stubNPM()
        options.timeout = 30
        return options
    }

    // MARK: - inspect

    func testInspectMissing() {
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .missing)
    }

    func testInspectCorruptWhenVersionMissing() throws {
        try installedPackageJSON(version: nil)
        let result = SDKInstaller.inspect(prefix: prefix)
        guard case .corrupt(let reason) = result else {
            return XCTFail("expected .corrupt, got \(result)")
        }
        XCTAssertTrue(reason.contains("version"), "reason should mention the version field: \(reason)")
    }

    func testInspectVersionMismatch() throws {
        try installedPackageJSON(version: "9.9.9")
        let result = SDKInstaller.inspect(prefix: prefix, expectedVersion: "1.0.0")
        XCTAssertEqual(result, .versionMismatch(actual: "9.9.9"))
    }

    func testInspectOK() throws {
        try installedPackageJSON(version: "1.0.0")
        XCTAssertEqual(
            SDKInstaller.inspect(prefix: prefix, expectedVersion: "1.0.0"),
            .ok(version: "1.0.0")
        )
    }

    // MARK: - install: success

    func testInstallSuccess() async throws {
        var options = try baseOptions()
        options.downloadURL = URL(string: "https://example.invalid/sdk.tgz")!
        options.reachabilityProbe = { _ in true }

        var streamed: [SDKInstaller.LogLine] = []
        let result = await SDKInstaller.install(options: options) { streamed.append($0) }

        XCTAssertTrue(result.success, "install should succeed; message: \(result.message)")
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.usedFallback)
        XCTAssertFalse(streamed.isEmpty, "live stdout should have been streamed")
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .ok(version: "1.0.0"))
    }

    func testInstallIsIdempotentWhenAlreadyOK() async throws {
        try installedPackageJSON(version: "1.0.0")
        var options = try baseOptions()
        // Point npm at a binary that must never run: idempotency means
        // inspect short-circuits before any subprocess spawns.
        options.npmExecutable = URL(fileURLWithPath: "/nonexistent/npm")
        options.reachabilityProbe = { _ in XCTFail("probe must not run when already installed"); return false }

        let result = await SDKInstaller.install(options: options)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.usedFallback)
    }

    // MARK: - install: unreachable -> fallback

    func testInstallFallsBackWhenGitHubUnreachable() async throws {
        var options = try baseOptions()
        options.downloadURL = URL(string: "https://unreachable.invalid/sdk.tgz")!
        options.reachabilityProbe = { _ in false }
        options.bundledFallbackURL = try fallbackSource()

        let result = await SDKInstaller.install(options: options)

        XCTAssertTrue(result.success, "fallback install should succeed; message: \(result.message)")
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertTrue(result.usedFallback, "result must honestly report the fallback was used")
        XCTAssertTrue(result.message.contains("bundled"), "message should state the fallback: \(result.message)")
    }

    func testInstallFailsHonestlyWhenUnreachableAndNoFallback() async throws {
        var options = try baseOptions()
        options.downloadURL = URL(string: "https://unreachable.invalid/sdk.tgz")!
        options.reachabilityProbe = { _ in false }
        options.bundledFallbackURL = tempDir.appendingPathComponent("no-such-dir")

        let result = await SDKInstaller.install(options: options)

        XCTAssertFalse(result.success)
        XCTAssertNil(result.installedVersion)
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.message.contains("unreachable"), "message must carry the real reason: \(result.message)")
    }

    // MARK: - install: corrupt

    func testInstallFailureReportsRealErrorText() async throws {
        var options = try baseOptions()
        // The stub exits 1 with an npm ERR! line for "unreachable" URLs…
        options.downloadURL = URL(string: "https://unreachable.invalid/sdk.tgz")!
        // …but the probe says reachable, so the GitHub path is attempted
        // and fails with the stub's real stderr.
        options.reachabilityProbe = { _ in true }
        options.bundledFallbackURL = tempDir.appendingPathComponent("no-such-dir")

        let result = await SDKInstaller.install(options: options)

        XCTAssertFalse(result.success, "a failed npm run must never report success")
        XCTAssertNil(result.installedVersion)
        XCTAssertTrue(
            result.message.contains("npm ERR!") || result.message.contains("exited with code 1"),
            "message must carry the REAL npm error text, got: \(result.message)"
        )
    }

    func testInstallFailsWhenNpmSucceedsButVerificationFails() async throws {
        var options = try baseOptions()
        options.downloadURL = URL(string: "https://example.invalid/sdk.tgz")!
        options.reachabilityProbe = { _ in true }
        // The stub honors STUB_WRITE_CORRUPT=1 by writing a package.json
        // with no version — npm "succeeds" but verification must fail.
        setenv("STUB_WRITE_CORRUPT", "1", 1)
        defer { unsetenv("STUB_WRITE_CORRUPT") }

        let result = await SDKInstaller.install(options: options)

        XCTAssertFalse(result.success, "verification failure must not be reported as success")
        XCTAssertNil(result.installedVersion)
        XCTAssertTrue(result.message.contains("version"), "message must explain the version problem: \(result.message)")
    }
}
