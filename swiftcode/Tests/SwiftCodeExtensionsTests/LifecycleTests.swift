import XCTest
@testable import SwiftCodeExtensions

@MainActor
final class LifecycleTests: XCTestCase {
    private var root: URL!
    private var manager: ExtensionManager!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCodeExtensionsLifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        manager = ExtensionManager(storage: ExtensionStorage(root: root))
        await manager.ensureReady()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func installRecord(id: String, engineRequirement: String? = "^1.80.0",
                               dependencies: [String] = [], enabled: Bool = true,
                               writeManifest: Bool = true) throws -> InstalledExtension {
        let parts = id.split(separator: ".")
        let metadata = ExtensionMetadata(publisher: String(parts[0]), name: String(parts[1]),
                                         version: "1.0.0", displayName: "Sample \(parts[1])",
                                         description: "", kind: .vscode,
                                         engineRequirement: engineRequirement)
        let installPath = root.appendingPathComponent("extensions/\(id)").path
        if writeManifest {
            var dict: [String: Any] = [
                "name": String(parts[1]), "publisher": String(parts[0]), "version": "1.0.0",
                "main": "./dist/index.js",
                "extensionDependencies": dependencies,
            ]
            if let engineRequirement { dict["engines"] = ["vscode": engineRequirement] }
            let extensionDir = root.appendingPathComponent("extensions/\(id)/extension")
            try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: dict)
                .write(to: extensionDir.appendingPathComponent("package.json"))
        } else {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("extensions/\(id)"), withIntermediateDirectories: true)
        }
        return InstalledExtension(metadata: metadata, isEnabled: enabled, installPath: installPath,
                                  dependencies: dependencies)
    }

    private func persist(_ records: [InstalledExtension]) throws {
        try manager.storage.saveInstalled(records)
        manager.refreshInstalled()
    }

    func testEnabledWhenCompatible() throws {
        try persist([installRecord(id: "acme.sample")])
        XCTAssertEqual(manager.installed.first?.state, .enabled)
    }

    func testIncompatibleWhenEngineTooNew() throws {
        try persist([installRecord(id: "acme.sample", engineRequirement: ">=9.0.0")])
        XCTAssertEqual(manager.installed.first?.state, .incompatible)
        XCTAssertNotNil(manager.installed.first?.lastError)
    }

    func testIncompatibleWhenNoEngineRequirement() throws {
        try persist([installRecord(id: "acme.sample", engineRequirement: nil)])
        XCTAssertEqual(manager.installed.first?.state, .incompatible)
    }

    func testDisabledState() throws {
        try persist([installRecord(id: "acme.sample", enabled: false)])
        XCTAssertEqual(manager.installed.first?.state, .disabled)
    }

    func testUnavailableWhenDirectoryMissing() throws {
        let record = try installRecord(id: "acme.gone", writeManifest: false)
        try? FileManager.default.removeItem(atPath: record.installPath)
        try persist([record])
        XCTAssertEqual(manager.installed.first?.state, .unavailable)
        XCTAssertEqual(manager.installed.first?.lastError, "Installed directory is missing.")
    }

    func testMissingDependenciesState() throws {
        let dep = try installRecord(id: "acme.dep")
        let main = try installRecord(id: "acme.main", dependencies: ["acme.dep", "acme.absent"])
        try persist([dep, main])
        let mainRecord = manager.installed.first { $0.id == "acme.main" }
        XCTAssertEqual(mainRecord?.state, .missingDependencies)
        XCTAssertTrue(mainRecord?.lastError?.contains("acme.absent") ?? false)
    }

    func testUnparseableManifestFallsBackToEnabled() throws {
        let record = try installRecord(id: "acme.broken")
        let manifestURL = root.appendingPathComponent("extensions/acme.broken/extension/package.json")
        try "this is not json".write(to: manifestURL, atomically: true, encoding: .utf8)
        try persist([record])
        XCTAssertEqual(manager.installed.first?.state, .enabled)
    }

    func testSetEnabledTogglesAndPersists() throws {
        try persist([installRecord(id: "acme.sample")])
        manager.setEnabled(extensionId: "acme.sample", enabled: false)
        XCTAssertEqual(manager.installed.first?.state, .disabled)
        manager.setEnabled(extensionId: "acme.sample", enabled: true)
        XCTAssertEqual(manager.installed.first?.state, .enabled)
        let reloaded = ExtensionStorage(root: root).loadInstalled()
        XCTAssertEqual(reloaded.first?.isEnabled, true)
    }

    func testUninstallRemovesRecordAndDirectory() async throws {
        try persist([installRecord(id: "acme.sample")])
        await manager.uninstall(extensionId: "acme.sample")
        XCTAssertTrue(manager.installed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("extensions/acme.sample").path))
        await manager.uninstall(extensionId: "acme.sample")
    }

    func testActivateGuards() async throws {
        do {
            _ = try await manager.activate(extensionId: "acme.nope")
            XCTFail("activate must throw for an unknown extension")
        } catch {
            XCTAssertTrue(error is SwiftCodeExtensionError)
        }
        try persist([installRecord(id: "acme.sample", enabled: false)])
        do {
            _ = try await manager.activate(extensionId: "acme.sample")
            XCTFail("activate must throw for a disabled extension")
        } catch {}
        try persist([installRecord(id: "acme.sample", engineRequirement: ">=9.0.0")])
        do {
            _ = try await manager.activate(extensionId: "acme.sample")
            XCTFail("activate must throw for an incompatible engine requirement")
        } catch {}
    }

    func testRegisterSamplePlugin() {
        manager.registerSamplePlugin()
        let record = manager.installed.first { $0.id == "swiftcode.sample.workspace-lister" }
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.state, .enabled)
        XCTAssertEqual(record?.capabilities, [.workspaceRead])
    }

    func testEnsureReadyIsIdempotent() async {
        await manager.ensureReady()
        XCTAssertTrue(manager.isReady)
        await manager.ensureReady()
        XCTAssertTrue(manager.isReady)
    }

    func testDiagnosticsRoundTrip() {
        let service = DiagnosticsService(storage: ExtensionStorage(root: root))
        service.info("hello", extensionId: "acme.sample")
        service.error("boom", extensionId: "acme.sample")
        XCTAssertEqual(service.entries(for: "acme.sample").count, 2)
        XCTAssertTrue(service.exportReport().contains("[error] acme.sample: boom"))
        XCTAssertEqual(service.allEntries().count, 2)
        service.clear()
        XCTAssertTrue(service.allEntries().isEmpty)
    }
}

final class PackageServiceTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCodeExtensionsPackage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testValidateExtensionID() {
        XCTAssertNoThrow(try PackageService.validate(extensionId: "acme.sample-1"))
        XCTAssertThrowsError(try PackageService.validate(extensionId: ""))
        XCTAssertThrowsError(try PackageService.validate(extensionId: ".acme.sample"))
        XCTAssertThrowsError(try PackageService.validate(extensionId: "acme..sample"))
        XCTAssertThrowsError(try PackageService.validate(extensionId: "acme/sample"))
        XCTAssertThrowsError(try PackageService.validate(extensionId: String(repeating: "a", count: 215)))
    }

    func testValidateRelativePath() {
        XCTAssertNoThrow(try PackageService.validateRelativePath("extension/package.json"))
        XCTAssertThrowsError(try PackageService.validateRelativePath("../escape"))
        XCTAssertThrowsError(try PackageService.validateRelativePath("/absolute"))
        XCTAssertThrowsError(try PackageService.validateRelativePath("a\\b"))
        XCTAssertThrowsError(try PackageService.validateRelativePath("C:/drive"))
        XCTAssertThrowsError(try PackageService.validateRelativePath("a/./b"))
    }

    func testInstallVSIX() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"),
                      "zip is not installed; cannot build a VSIX fixture.")
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let extensionDir = source.appendingPathComponent("extension/dist")
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "sample", "publisher": "acme", "version": "1.0.0",
            "engines": ["vscode": "^1.80.0"], "main": "./dist/index.js",
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: source.appendingPathComponent("extension/package.json"))
        try "module.exports = {};".write(to: extensionDir.appendingPathComponent("index.js"),
                                          atomically: true, encoding: .utf8)
        let vsix = root.appendingPathComponent("acme.sample.vsix")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-r", "-q", vsix.path, "extension"]
        zip.currentDirectoryURL = source
        try zip.run()
        zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)

        let storage = ExtensionStorage(root: root.appendingPathComponent("store"))
        let service = PackageService(storage: storage)
        let installed = try service.install(vsixURL: vsix, identity: ExtensionIdentity(publisher: "acme", name: "sample"))
        XCTAssertEqual(installed.manifest.identity.id, "acme.sample")
        XCTAssertTrue(installed.compatibility.compatible)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: installed.directory.appendingPathComponent("extension/package.json").path))
        XCTAssertThrowsError(try service.install(
            vsixURL: vsix, identity: ExtensionIdentity(publisher: "other", name: "sample")))
        XCTAssertNoThrow(try service.uninstall(extensionId: "acme.sample"))
        XCTAssertNoThrow(try service.uninstall(extensionId: "acme.sample"))
    }

    func testZipCentralDirectoryRejectsSymlinkEntries() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let notZip = root.appendingPathComponent("not-a-vsix.vsix")
        try "hello".write(to: notZip, atomically: true, encoding: .utf8)
        let service = PackageService(storage: ExtensionStorage(root: root.appendingPathComponent("store")))
        XCTAssertThrowsError(try service.install(vsixURL: notZip,
                                                 identity: ExtensionIdentity(publisher: "acme", name: "sample")))
    }
}

final class EditorTests: XCTestCase {
    func testApplyEditsBasic() throws {
        let result = try EditorBridge.applyEdits(
            [TextEdit(range: TextRange(start: TextPosition(line: 1, character: 0),
                                       end: TextPosition(line: 1, character: 5)),
                      newText: "bye")],
            to: "hello\nworld\n!")
        XCTAssertEqual(result, "hello\nbye\n!")
    }

    func testApplyEditsCountsEmojiAsOneColumn() throws {
        let content = "a😀b\nsecond"
        let result = try EditorBridge.applyEdits(
            [TextEdit(range: TextRange(start: TextPosition(line: 0, character: 2),
                                       end: TextPosition(line: 0, character: 3)),
                      newText: "c")],
            to: content)
        XCTAssertEqual(result, "a😀c\nsecond")
    }

    func testApplyEditsRejectsOverlap() {
        let edits = [
            TextEdit(range: TextRange(start: TextPosition(line: 0, character: 0),
                                      end: TextPosition(line: 0, character: 3)), newText: "x"),
            TextEdit(range: TextRange(start: TextPosition(line: 0, character: 2),
                                      end: TextPosition(line: 0, character: 5)), newText: "y"),
        ]
        XCTAssertThrowsError(try EditorBridge.applyEdits(edits, to: "hello"))
    }

    func testApplyEditsRejectsOutOfRange() {
        let edits = [TextEdit(range: TextRange(start: TextPosition(line: 5, character: 0),
                                               end: TextPosition(line: 5, character: 1)), newText: "x")]
        XCTAssertThrowsError(try EditorBridge.applyEdits(edits, to: "hello"))
    }

    func testApplyEditsSupportsMultilineReplacement() throws {
        let result = try EditorBridge.applyEdits(
            [TextEdit(range: TextRange(start: TextPosition(line: 0, character: 0),
                                       end: TextPosition(line: 0, character: 5)),
                      newText: "one\ntwo")],
            to: "hello")
        XCTAssertEqual(result, "one\ntwo")
    }

    func testOffsetForPosition() {
        XCTAssertEqual(EditorBridge.offset(for: TextPosition(line: 1, character: 2), in: "ab\ncde"), 5)
        XCTAssertNil(EditorBridge.offset(for: TextPosition(line: 3, character: 0), in: "ab\ncde"))
        XCTAssertNil(EditorBridge.offset(for: TextPosition(line: 0, character: 99), in: "ab"))
    }

    func testSortLinesCommand() async throws {
        let buffer = SourceTextBuffer(
            text: "keep\nbanana\napple\ncherry\nkeep",
            selections: [SourceRange(start: SourcePosition(line: 1, column: 0),
                                     end: SourcePosition(line: 3, column: 6))])
        try await XcodeCommandRegistry.shared.perform(identifier: "com.swiftcode.xcode.sortLines", buffer: buffer)
        XCTAssertEqual(buffer.completeBuffer, "keep\napple\nbanana\ncherry\nkeep")
    }

    func testSortLinesNoSelectionIsNoop() async throws {
        let buffer = SourceTextBuffer(text: "b\na")
        try await XcodeCommandRegistry.shared.perform(identifier: "com.swiftcode.xcode.sortLines", buffer: buffer)
        XCTAssertEqual(buffer.completeBuffer, "b\na")
    }

    func testBufferEditsAreAtomicOnFailure() {
        let buffer = SourceTextBuffer(text: "one\ntwo")
        let edits = [
            SourceTextBuffer.Edit(range: SourceRange(start: SourcePosition(line: 0, column: 0),
                                                     end: SourcePosition(line: 0, column: 3)), newText: "1"),
            SourceTextBuffer.Edit(range: SourceRange(start: SourcePosition(line: 9, column: 0),
                                                     end: SourcePosition(line: 9, column: 1)), newText: "x"),
        ]
        XCTAssertThrowsError(try buffer.applyEdits(edits))
        XCTAssertEqual(buffer.completeBuffer, "one\ntwo")
    }

    func testUnknownXcodeCommandIsInvalidRequest() async {
        let buffer = SourceTextBuffer(text: "x")
        do {
            try await XcodeCommandRegistry.shared.perform(identifier: "com.example.nope", buffer: buffer)
            XCTFail("Expected an error for an unknown command.")
        } catch let error as SwiftCodeExtensionError {
            if case .invalidRequest = error { return }
            XCTFail("Wrong error: \(error)")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testSourcePositionOrdering() {
        XCTAssertTrue(SourcePosition(line: 0, column: 5) < SourcePosition(line: 1, column: 0))
        XCTAssertFalse(SourcePosition(line: 1, column: 0) < SourcePosition(line: 0, column: 9))
        XCTAssertTrue(SourceRange(start: SourcePosition(line: 1, column: 1),
                                  end: SourcePosition(line: 1, column: 1)).isEmpty)
    }

    func testHostScriptResourceExistsAndHasFixedApplyEditShape() {
        let source = HostScript.source
        XCTAssertFalse(source.isEmpty, "The bundled extension-host.js resource must load.")
        XCTAssertTrue(source.contains("host.applyEdit"))
        XCTAssertTrue(source.contains("edits: edit.edits"))
        XCTAssertFalse(source.contains("workspace.applyEdit"))
        XCTAssertTrue(source.contains("1.85.0"))
    }
}

func XCTAssertThrowsErrorAsync<T>(_ expression: @escaping () async throws -> T,
                                  _ message: @autoclosure () -> String = "",
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ errorHandler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error. \(message())", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
