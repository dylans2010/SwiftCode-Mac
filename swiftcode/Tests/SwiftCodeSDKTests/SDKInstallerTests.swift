import XCTest
@testable import SwiftCodeSDK

final class SDKInstallerTests: XCTestCase {
    private func makePrefix() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sdk-installer-test-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePackage(at prefix: URL, name: String = "@swiftcode/sdk", version: String = "1.0.0", entries: Bool = true) throws {
        let packageDir = prefix
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("@swiftcode", isDirectory: true)
            .appendingPathComponent("sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let packageJSON = ["name": name, "version": version]
        let data = try JSONSerialization.data(withJSONObject: packageJSON)
        try data.write(to: packageDir.appendingPathComponent("package.json"))
        if entries {
            for entry in ["dist/index.js", "dist/index.d.ts", "dist/assist.js", "dist/assistUI.js"] {
                let url = packageDir.appendingPathComponent(entry)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("// stub".utf8).write(to: url)
            }
        }
    }

    func testMissingWhenNothingInstalled() {
        XCTAssertEqual(SDKInstaller.inspect(prefix: makePrefix()), .missing)
    }

    func testOkWhenInstallIsComplete() throws {
        let prefix = makePrefix()
        try writePackage(at: prefix)
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .ok(version: "1.0.0"))
    }

    func testVersionMismatch() throws {
        let prefix = makePrefix()
        try writePackage(at: prefix, version: "0.9.0")
        XCTAssertEqual(SDKInstaller.inspect(prefix: prefix), .versionMismatch(actual: "0.9.0"))
    }

    func testCorruptWhenEntriesMissing() throws {
        let prefix = makePrefix()
        try writePackage(at: prefix, entries: false)
        let inspection = SDKInstaller.inspect(prefix: prefix)
        if case .corrupt = inspection { return }
        XCTFail("Expected .corrupt, got \(inspection)")
    }

    func testCorruptWhenWrongPackage() throws {
        let prefix = makePrefix()
        try writePackage(at: prefix, name: "@someone/else")
        let inspection = SDKInstaller.inspect(prefix: prefix)
        if case .corrupt = inspection { return }
        XCTFail("Expected .corrupt, got \(inspection)")
    }

    func testInstallShortCircuitsWhenAlreadyOk() async throws {
        let prefix = makePrefix()
        try writePackage(at: prefix)
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.reachabilityProbe = { _ in
            XCTFail("Reachability probe must not run when already installed")
            return false
        }
        let result = await SDKInstaller.install(options: options)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.installedVersion, "1.0.0")
        XCTAssertFalse(result.usedFallback)
        XCTAssertTrue(result.log.isEmpty)
    }

    func testInstallFailsHonestlyWithNoSource() async throws {
        let prefix = makePrefix()
        var options = SDKInstaller.InstallOptions()
        options.prefix = prefix
        options.reachabilityProbe = { _ in false }
        options.bundledFallbackURL = prefix.appendingPathComponent("does-not-exist.tgz")
        let result = await SDKInstaller.install(options: options)
        XCTAssertFalse(result.success)
        XCTAssertFalse(result.usedFallback)
    }

    func testBundledFallbackIsAbsentWithReason() {
        let status = SDKInstaller.bundledFallbackStatus()
        switch status {
        case .present(let url):
            XCTFail("Expected no bundled SDK copy, found one at \(url.path) — update this test to assert .present.")
        case .absent(let reason):
            XCTAssertTrue(reason.contains("No SDK tarball ships in this repo."))
            XCTAssertTrue(reason.contains("npm pack"))
            XCTAssertTrue(reason.contains("sdk-v1.0.0"))
        }
    }
}
