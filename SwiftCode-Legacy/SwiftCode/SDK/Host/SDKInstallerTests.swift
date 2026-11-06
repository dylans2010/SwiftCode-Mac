// These tests can run against SDKInstaller.swift in an isolated SwiftPM
// target named SwiftCode; the app itself has no XCTest target.

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

private final class InstallerTestLines: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [SDKInstaller.LogLine] = []
    func append(_ line: SDKInstaller.LogLine) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(line)
    }
    var lines: [SDKInstaller.LogLine] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

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
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dist"), withIntermediateDirectories: true)
        for file in ["index.js", "index.d.ts", "assist.js", "assistUI.js"] {
            try "export {};".write(to: dir.appendingPathComponent("dist/\(file)"), atomically: true, encoding: .utf8)
        }
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
        mkdir -p "$TARGET/dist"
        printf 'export {};' > "$TARGET/dist/index.js"
        printf 'export {};' > "$TARGET/dist/index.d.ts"
        printf 'export {};' > "$TARGET/dist/assist.js"
        printf 'export {};' > "$TARGET/dist/assistUI.js"
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

    func testInspectRejectsMissingEntrypoint() throws {
        try installedPackageJSON(version: "1.0.0")
        try FileManager.default.removeItem(at: prefix.appendingPathComponent("node_modules/@swiftcode/sdk/dist/index.js"))
        guard case .corrupt = SDKInstaller.inspect(prefix: prefix) else {
            return XCTFail("A package.json without runtime code must not count as installed")
        }
    }

    func testInspectRejectsMissingName() throws {
        try installedPackageJSON(version: "1.0.0")
        try Data("{\"version\":\"1.0.0\"}".utf8).write(to: prefix.appendingPathComponent("node_modules/@swiftcode/sdk/package.json"))
        guard case .corrupt = SDKInstaller.inspect(prefix: prefix) else {
            return XCTFail("A version alone must not count as the SDK")
        }
    }

    func testFailedNpmCannotReportSuccessEvenIfItWroteFiles() async throws {
        var options = try baseOptions()
        let script = try XCTUnwrap(options.npmExecutable)
        let body = try String(contentsOf: script, encoding: .utf8)
        try body.replacingOccurrences(of: "exit 0", with: "exit 1").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        options.reachabilityProbe = { _ in true }
        options.bundledFallbackURL = tempDir.appendingPathComponent("absent")
        let result = await SDKInstaller.install(options: options)
        XCTAssertFalse(result.success)
    }

    func testRealBundledTarballInstallsAndImports() async throws {
        guard let source = ProcessInfo.processInfo.environment["SWIFTCODE_TEST_SDK_TARBALL"] else {
            throw NSError(domain: "SDKInstallerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Set SWIFTCODE_TEST_SDK_TARBALL to the release archive"])
        }
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.reachabilityProbe = { _ in false }
        options.bundledFallbackURL = URL(fileURLWithPath: source)
        let result = await SDKInstaller.install(options: options)
        XCTAssertTrue(result.success, result.message)
        XCTAssertTrue(result.usedFallback)
        let node = Process()
        node.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        node.arguments = ["node", "--input-type=module", "-e", "import { createContext, createAssistAPI, createAssistUIAPI } from '@swiftcode/sdk'; if (![createContext, createAssistAPI, createAssistUIAPI].every(x => typeof x === 'function')) process.exit(1)"]
        node.currentDirectoryURL = prefix
        try node.run()
        node.waitUntilExit()
        XCTAssertEqual(node.terminationStatus, 0, "The installed SDK must import, not just have a package.json")
    }

    func testRealRemoteDownloadOrBundledFallbackImports() async throws {
        let source = try XCTUnwrap(ProcessInfo.processInfo.environment["SWIFTCODE_TEST_SDK_TARBALL"])
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.bundledFallbackURL = URL(fileURLWithPath: source)
        options.timeout = 60
        let result = await SDKInstaller.install(options: options)
        XCTAssertTrue(result.success, result.message)
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .ok(version: "1.0.0"))
        print("Live SDK download verification: \(result.message)")
    }

    // MARK: - install: success

    func testInstallSuccess() async throws {
        var options = try baseOptions()
        options.downloadURL = URL(string: "https://example.invalid/sdk.tgz")!
        options.reachabilityProbe = { _ in true }

        let streamed = InstallerTestLines()
        let result = await SDKInstaller.install(options: options) { streamed.append($0) }

        XCTAssertTrue(result.success, "install should succeed; message: \(result.message)")
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.usedFallback)
        XCTAssertFalse(streamed.lines.isEmpty, "live stdout should have been streamed")
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
