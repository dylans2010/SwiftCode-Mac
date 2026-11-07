import Foundation
import XCTest
@testable import SwiftCodeExtensions
import SwiftCodeSDK
import SwiftCodeSDKStudio

@MainActor
final class SDKStudioEditorTests: XCTestCase {
    private var tmp: URL!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.sdk.studio.codeEditor.projectRootPath")
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCodeSDKStudioTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.sdk.studio.codeEditor.projectRootPath")
        super.tearDown()
    }

    func testCodeLanguageInference() {
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: "swift"), .swift)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: ".tsx"), .typescript)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: "mjs"), .javascript)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: "md"), .markdown)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: "xyz"), .plaintext)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileExtension: ""), .plaintext)
        XCTAssertEqual(SDKCodeLanguage.infer(fromFileURL: URL(fileURLWithPath: "/x/ContentView.swift")), .swift)
        XCTAssertEqual(SDKCodeLanguage.swift.displayName, "Swift")
        XCTAssertEqual(SDKCodeLanguage.typescript.fileExtensions, ["ts", "tsx", "mts", "cts"])
    }

    func testKeywordHighlighter() {
        let highlighter = SDKKeywordHighlighter()
        let tokens = highlighter.highlight("let x = 42 // hi\nlet s = \"str\"", language: .swift)
        XCTAssertTrue(tokens.contains { $0.kind == .keyword })
        XCTAssertTrue(tokens.contains { $0.kind == .number })
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
        XCTAssertTrue(tokens.contains { $0.kind == .string })
        var previousEnd = 0
        for token in tokens {
            XCTAssertGreaterThanOrEqual(token.range.lowerBound, previousEnd)
            XCTAssertLessThanOrEqual(token.range.upperBound, "let x = 42 // hi\nlet s = \"str\"".utf16.count)
            previousEnd = token.range.upperBound
        }
        let typeTokens = highlighter.highlight("let v: ContentView = ContentView()", language: .swift)
        XCTAssertTrue(typeTokens.contains { $0.kind == .typeName })
        XCTAssertTrue(highlighter.highlight("hello world", language: .plaintext).isEmpty)
        XCTAssertTrue(highlighter.highlight("", language: .swift).isEmpty)
        let nested = highlighter.highlight("/* outer /* inner */ still */ let a = 1", language: .swift)
        XCTAssertEqual(nested.filter { $0.kind == .comment }.count, 1)
        XCTAssertTrue(nested.contains { $0.kind == .keyword })
    }

    func testCodeDocument() {
        let doc = SDKCodeDocument(fileURL: URL(fileURLWithPath: "/x/a.ts"), language: .typescript, text: "hi")
        XCTAssertEqual(doc.displayName, "a.ts")
        XCTAssertFalse(doc.isDirty)
        let edited = doc.withText("hello")
        XCTAssertTrue(edited.isDirty)
        XCTAssertEqual(edited.text, "hello")
        XCTAssertFalse(edited.saved().isDirty)
        XCTAssertEqual(SDKCodeDocument(fileURL: nil, language: .swift, text: "").displayName, "Untitled.ts")
    }

    func testFileNodeInvariants() {
        let file = SDKCodeFileNode(url: URL(fileURLWithPath: "/x/a.ts"), isDirectory: false,
                                   children: [SDKCodeFileNode(url: URL(fileURLWithPath: "/x/b.ts"), isDirectory: false)])
        XCTAssertNil(file.children, "Files never carry children")
        XCTAssertFalse(file.needsLoading)
        let dir = SDKCodeFileNode(url: URL(fileURLWithPath: "/x"), isDirectory: true)
        XCTAssertTrue(dir.needsLoading)
        let toggled = dir.toggledExpanded()
        XCTAssertTrue(toggled.isExpanded)
        XCTAssertTrue(toggled.withChildren([file]).children?.count == 1)
    }

    func testEditorStateTabs() throws {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        let file = tmp.appendingPathComponent("index.ts")
        try "const a = 1;\n".write(to: file, atomically: true, encoding: .utf8)
        let tabID = try state.openFile(file)
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertEqual(state.activeTabID, tabID)
        XCTAssertEqual(state.activeDocument?.language, .typescript)
        XCTAssertEqual(try state.openFile(file), tabID)
        XCTAssertEqual(state.tabs.count, 1)
        state.updateText("const a = 2;\n", for: tabID)
        XCTAssertTrue(state.hasUnsavedChanges)
        state.saveAllModifiedTabs()
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "const a = 2;\n")
        let untitled = state.newUntitledTab(language: .swift, initialText: "let x = 1")
        XCTAssertEqual(state.tabs.count, 2)
        XCTAssertEqual(state.activeTabID, untitled)
        state.closeTab(untitled)
        XCTAssertEqual(state.activeTabID, tabID)
        XCTAssertThrowsError(try state.openFile(tmp.appendingPathComponent("missing.swift")))
        XCTAssertThrowsError(try state.openFile(tmp.appendingPathComponent("nope.txt")))
    }

    func testEditorStateConsoleBounds() {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        state.appendConsole(.system(String(repeating: "x", count: 10_000)))
        XCTAssertEqual(state.consoleEntries.count, 1)
        XCTAssertLessThanOrEqual(state.consoleEntries[0].text.count, SDKConsoleEntry.maxTextLength + 20)
        XCTAssertTrue(state.consoleEntries[0].text.contains("truncated"))
        for _ in 0..<SDKCodeEditorState.maxConsoleEntries + 10 {
            state.appendConsole(.stdout("line"))
        }
        XCTAssertEqual(state.consoleEntries.count, SDKCodeEditorState.maxConsoleEntries)
        state.clearConsole()
        XCTAssertTrue(state.consoleEntries.isEmpty)
    }

    func testEditorStateExternalModification() throws {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        let file = tmp.appendingPathComponent("a.swift")
        try "let a = 1\n".write(to: file, atomically: true, encoding: .utf8)
        let tabID = try state.openFile(file)
        try "let a = 2\n".write(to: file, atomically: true, encoding: .utf8)
        state.updateDocument(forTab: tabID) { doc in
            SDKCodeDocument(id: doc.id, fileURL: doc.fileURL, language: doc.language, text: doc.text,
                            isDirty: false, lastKnownModificationDate: Date.distantPast)
        }
        state.checkExternalModifications()
        XCTAssertEqual(state.activeDocument?.text, "let a = 2\n")
        state.updateText("let a = 3\n", for: tabID)
        state.updateDocument(forTab: tabID) { doc in
            SDKCodeDocument(id: doc.id, fileURL: doc.fileURL, language: doc.language, text: doc.text,
                            isDirty: true, cursorOffset: doc.cursorOffset,
                            lastKnownModificationDate: Date.distantPast, hasExternalModification: false)
        }
        try "let a = 4\n".write(to: file, atomically: true, encoding: .utf8)
        state.checkExternalModifications()
        XCTAssertTrue(state.externalModificationTabIDs.contains(tabID))
        XCTAssertEqual(state.activeDocument?.text, "let a = 3\n")
        try state.reloadTabFromDisk(tabID)
        XCTAssertEqual(state.activeDocument?.text, "let a = 4\n")
        XCTAssertFalse(state.externalModificationTabIDs.contains(tabID))
    }

    func testEditorStateDiagnosticsAndNavigation() {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        let diag = SDKEditorDiagnostic(severity: .error, source: "swiftcode.json", code: "MANIFEST_READ_ERROR",
                                       message: "boom", fileURL: tmp, line: 1)
        state.appendDiagnostic(diag)
        state.appendDiagnostic(diag)
        XCTAssertEqual(state.diagnostics.count, 1, "Duplicates are deduplicated")
        state.clearDiagnostics()
        XCTAssertTrue(state.diagnostics.isEmpty)
        state.navigateActiveTabTo(line: 3)
        XCTAssertNil(state.requestedNavigationTarget, "No active tab — no target")
        let tabID = state.newUntitledTab()
        state.navigateActiveTabTo(line: 3, column: 5)
        XCTAssertEqual(state.requestedNavigationTarget?.tabID, tabID)
        XCTAssertEqual(state.requestedNavigationTarget?.line, 3)
        XCTAssertEqual(state.requestedNavigationTarget?.column, 5)
        state.clearNavigationTarget()
        XCTAssertNil(state.requestedNavigationTarget)
    }

    func testEditorStateSnippetAndManifest() throws {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        state.insertCodeSnippet("const hello = 1;")
        XCTAssertEqual(state.tabs.count, 1)
        XCTAssertTrue(state.activeDocument?.text.contains("const hello = 1;") ?? false)
        let manifestURL = tmp.appendingPathComponent("swiftcode.json")
        try """
        {"manifestVersion": 1, "id": "com.example.x", "name": "X", "version": "1.0.0", "type": "extension",
         "runtime": {"language": "typescript", "entrypoint": "dist/index.js", "minimumSwiftCodeVersion": "1.0.0"},
         "sdk": {"name": "@swiftcode/sdk", "versionRange": "^1.0.0", "protocolVersion": 1},
         "capabilities": [], "assist": {"requested": false}}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(state.addCapabilityToManifest(capabilityId: "workspace.read", reason: "Read files."))
        let decoded = try JSONDecoder().decode(SwiftCodeManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertTrue(decoded.capabilities.contains { $0.id == "workspace.read" })
        XCTAssertTrue(state.addCapabilityToManifest(capabilityId: "workspace.read", reason: "x"),
                      "Adding an existing capability updates its reason and still returns true")
    }

    func testFindCoordinator() {
        final class StubEditor: SDKCodeFindableEditor {
            var text: String
            var selected: [Range<Int>] = []
            init(text: String) { self.text = text }
            var findableText: String { text }
            func selectFindRange(_ range: Range<Int>) { selected.append(range) }
        }
        let coordinator = SDKCodeFindCoordinator()
        let stub = StubEditor(text: "foo bar Foo foo")
        coordinator.editor = stub
        coordinator.setQuery("foo")
        XCTAssertEqual(coordinator.matches.count, 3)
        XCTAssertEqual(coordinator.matchSummaryText, "1 of 3")
        XCTAssertTrue(coordinator.hasMatches)
        coordinator.findNext()
        XCTAssertEqual(coordinator.matchSummaryText, "2 of 3")
        coordinator.findNext()
        coordinator.findNext()
        XCTAssertEqual(coordinator.matchSummaryText, "1 of 3", "Next wraps around")
        coordinator.findPrevious()
        XCTAssertEqual(coordinator.matchSummaryText, "3 of 3")
        coordinator.caseSensitive = true
        XCTAssertEqual(coordinator.matches.count, 2, "Case-sensitive drops the capital Foo")
        coordinator.setQuery("zzz")
        XCTAssertEqual(coordinator.matchSummaryText, "No matches")
        XCTAssertFalse(coordinator.hasMatches)
        coordinator.setQuery("")
        XCTAssertEqual(coordinator.matchSummaryText, "")
        stub.text = "foo foo"
        coordinator.setQuery("foo")
        stub.text = "foo foo foo"
        coordinator.editorTextDidChange()
        XCTAssertEqual(coordinator.matches.count, 3)
    }

    func testSnippetStore() {
        let snippets = SDKSnippetStore.loadAll()
        XCTAssertEqual(snippets.count, SDKCapabilityID.allCases.count)
        for cap in SDKCapabilityID.allCases {
            XCTAssertTrue(snippets.contains { $0.capabilityId == cap.rawValue },
                          "Every canonical capability has a snippet: \(cap.rawValue)")
        }
        let filtered = SDKSnippetStore.filter(snippets, query: "workspace.read")
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.allSatisfy { $0.capabilityId.contains("workspace") || $0.code.contains("workspace.read") })
        let build = SDKSnippetStore.filter(snippets, query: "", category: .build)
        XCTAssertTrue(build.contains { $0.capabilityId == "build.execute" })
        XCTAssertFalse(build.contains { $0.capabilityId == "workspace.read" })
        let snippet = snippets.first { $0.capabilityId == "workspace.read" }!
        XCTAssertTrue(snippet.executableCode(for: .typescript).contains("workspace.read"))
        XCTAssertTrue(snippet.executableCode(for: .manifest).contains("\"id\": \"workspace.read\""))
    }

    func testBuildRunnerValidation() async throws {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        let valid = await SDKCodeBuildRunner.shared.validateProject(at: tmp, into: state)
        XCTAssertTrue(valid)
        XCTAssertTrue(state.diagnostics.contains { $0.code == "NO_MANIFEST_OR_PROJECT" })
        try """
        {"manifestVersion": 2, "id": "", "name": "X", "version": "bad", "type": "extension"}
        """.write(to: tmp.appendingPathComponent("swiftcode.json"), atomically: true, encoding: .utf8)
        let invalidValid = await SDKCodeBuildRunner.shared.validateProject(at: tmp, into: state)
        XCTAssertFalse(invalidValid)
        XCTAssertFalse(state.diagnostics.isEmpty)
        XCTAssertTrue(state.diagnostics.allSatisfy { $0.severity == .error || $0.severity == .warning })
    }
    func testManagedBuildFailsHonestlyWithoutGrant() async {
        let state = SDKCodeEditorState(projectRootURL: tmp)
        await SDKCodeBuildRunner.shared.run(
            SDKBuildRunRequest(projectRoot: tmp, kind: .xcodebuildSwift, schemeOrEntry: "MyScheme"),
            into: state)
        XCTAssertTrue(state.diagnostics.contains { $0.code == "PERMISSION_DENIED" })
        XCTAssertTrue(state.diagnostics.allSatisfy { $0.severity == .error })
        XCTAssertFalse(state.consoleEntries.isEmpty)
    }
}

@MainActor
final class SDKStudioModelTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftCodeSDKStudioModelTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suiteName = "SwiftCodeSDKStudioModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstLaunchChoice() {
        XCTAssertTrue(SDKStudioFirstLaunchChoice.shouldPrompt(sdkInstalled: false, defaults: defaults))
        XCTAssertFalse(SDKStudioFirstLaunchChoice.shouldPrompt(sdkInstalled: true, defaults: defaults))
        SDKStudioFirstLaunchChoice.recordRemindLater(defaults: defaults)
        XCTAssertFalse(SDKStudioFirstLaunchChoice.shouldPrompt(sdkInstalled: false, defaults: defaults))
        XCTAssertEqual(SDKStudioFirstLaunchChoice.recordedChoice(defaults: defaults), .remindLater)
        SDKStudioFirstLaunchChoice.recordDeclined(defaults: defaults)
        XCTAssertEqual(SDKStudioFirstLaunchChoice.recordedChoice(defaults: defaults), .declined)
        SDKStudioFirstLaunchChoice.recordInstalled(defaults: defaults)
        XCTAssertEqual(SDKStudioFirstLaunchChoice.recordedChoice(defaults: defaults), .installed)
    }

    func testInstallerUnavailable() async {
        let installer = SDKStudioInstallerUnavailable()
        XCTAssertEqual(installer.inspect(), .notInstalled)
        XCTAssertNil(installer.bundledFallbackURL())
        let result = await installer.install { _ in }
        XCTAssertFalse(result.succeeded)
    }

    func testWizardValidators() {
        XCTAssertNil(SDKStudioWizardValidators.extensionID("com.example.my-ext"))
        XCTAssertNotNil(SDKStudioWizardValidators.extensionID("no-dot"))
        XCTAssertNotNil(SDKStudioWizardValidators.extensionID(""))
        XCTAssertNil(SDKStudioWizardValidators.semver("0.1.0"))
        XCTAssertNil(SDKStudioWizardValidators.semver("1.2.3-beta.1"))
        XCTAssertNotNil(SDKStudioWizardValidators.semver("1.2"))
        XCTAssertNil(SDKStudioWizardValidators.npmSlug("my-project"))
        XCTAssertNotNil(SDKStudioWizardValidators.npmSlug("My Project"))
        XCTAssertNil(SDKStudioWizardValidators.swiftTypeName("MyApp"))
        XCTAssertNotNil(SDKStudioWizardValidators.swiftTypeName("1App"))
        XCTAssertNotNil(SDKStudioWizardValidators.targetDirectory(""))
        XCTAssertNil(SDKStudioWizardValidators.targetDirectory(tmp.path))
        XCTAssertNil(SDKStudioWizardValidators.description(""))
        XCTAssertNotNil(SDKStudioWizardValidators.description(String(repeating: "x", count: 1001)))
    }

    func testScaffoldCreatesProjects() throws {
        let extDir = tmp.appendingPathComponent("MyExt")
        let (target, written) = try SDKStudioScaffold.create(
            config: .newExtension,
            values: ["id": "com.example.myext", "name": "My Ext", "version": "0.1.0",
                     "description": "Test", "outDir": extDir.path, "sdkPackage": ""])
        XCTAssertEqual(target, extDir.standardizedFileURL)
        XCTAssertTrue(written.contains("swiftcode.json"))
        XCTAssertTrue(written.contains("src/index.ts"))
        let manifest = try JSONDecoder().decode(
            SwiftCodeManifest.self, from: Data(contentsOf: extDir.appendingPathComponent("swiftcode.json")))
        XCTAssertEqual(manifest.id, "com.example.myext")
        XCTAssertTrue(manifest.capabilities.contains { $0.id == "build.execute" })
        XCTAssertThrowsError(try SDKStudioScaffold.create(
            config: .newExtension,
            values: ["id": "com.example.other", "name": "Other", "version": "0.1.0",
                     "description": "", "outDir": extDir.path, "sdkPackage": ""]))
        let swiftDir = tmp.appendingPathComponent("MyApp")
        let (_, swiftWritten) = try SDKStudioScaffold.create(
            config: .newSwiftProject,
            values: ["name": "MyApp", "bundleId": "com.example.myapp", "outDir": swiftDir.path])
        XCTAssertTrue(swiftWritten.contains("App.swift"))
        XCTAssertTrue(swiftWritten.contains("ContentView.swift"))
        XCTAssertTrue(try String(contentsOf: swiftDir.appendingPathComponent("App.swift"), encoding: .utf8)
            .contains("struct MyAppApp"))
        let tsDir = tmp.appendingPathComponent("MyTS")
        let (_, tsWritten) = try SDKStudioScaffold.create(
            config: .newTypeScriptProject,
            values: ["name": "My TS", "slug": "my-ts", "version": "0.1.0",
                     "description": "", "outDir": tsDir.path])
        XCTAssertTrue(tsWritten.contains("package.json"))
    }

    func testRecentProjects() {
        XCTAssertTrue(SDKStudioRecentProjects.load(defaults: defaults).isEmpty)
        let dir = tmp.appendingPathComponent("P")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        SDKStudioRecentProjects.record(dir, defaults: defaults)
        SDKStudioRecentProjects.record(tmp, defaults: defaults)
        let loaded = SDKStudioRecentProjects.load(defaults: defaults)
        XCTAssertEqual(loaded.first, tmp.standardizedFileURL.path, "Most recent first")
        XCTAssertEqual(loaded.count, 2)
        SDKStudioRecentProjects.record(tmp.appendingPathComponent("Gone"), defaults: defaults)
        XCTAssertFalse(SDKStudioRecentProjects.load(defaults: defaults)
            .contains(tmp.appendingPathComponent("Gone").path))
        SDKStudioRecentProjects.clear(defaults: defaults)
        XCTAssertTrue(SDKStudioRecentProjects.load(defaults: defaults).isEmpty)
    }

    func testGrantStoreAdapter() async throws {
        let permissions = PermissionManager(grants: ["com.example.ext": [.workspaceRead, .network]])
        let records = SDKGrantStore(storeURL: tmp.appendingPathComponent("SDKGrants.json"))
        let store = SDKPermissionManagerGrantStore(permissions: permissions, grantRecords: records)
        let grants = try await store.grants(for: "com.example.ext")
        XCTAssertFalse(grants.isEmpty)
        XCTAssertTrue(grants.allSatisfy { $0.isActive() })
        XCTAssertTrue(grants.contains { $0.capability == .workspaceRead })
        let first = grants[0]
        let other: SDKCapabilityID = first.capability == .workspaceRead ? .networkRequest : .workspaceRead
        try await store.revoke(first)
        let remaining = try await store.grants(for: "com.example.ext")
        let revoked = remaining.first { $0.capability == first.capability }
        XCTAssertNotNil(revoked)
        XCTAssertNotNil(revoked?.revokedAt)
        XCTAssertFalse(revoked?.isActive() ?? true)
        XCTAssertTrue(remaining.contains { $0.capability == other && $0.isActive() })
        try await store.revokeAll(for: "com.example.ext")
        let afterAll = try await store.grants(for: "com.example.ext")
        XCTAssertFalse(afterAll.isEmpty, "revokeAll stamps tombstones; it does not delete records")
        XCTAssertTrue(afterAll.allSatisfy { $0.revokedAt != nil })
        XCTAssertTrue(afterAll.allSatisfy { !$0.isActive() })
        let missingName = await store.extensionName(for: "com.example.ext")
        XCTAssertNil(missingName)
    }

    func testGrantStoreAdapterTombstoneResolvesExtensionName() async throws {
        let extensionID = "com.swiftcode.sdk.test.tombstone-name"
        let digest = String(repeating: "b", count: 64)
        let manifest = SwiftCodeManifest(id: extensionID, name: "Tombstone Test App", version: "1.0.0-test")
        let install = SDKInstalledExtension(
            id: extensionID, name: "Tombstone Test App", version: "1.0.0-test",
            packageDigest: digest,
            installPath: tmp.appendingPathComponent("TombstoneApp"),
            installedAt: Date(), updatedAt: Date(), enabled: true, manifest: manifest)
        try await SDKExtensionRegistry.shared.recordInstall(install)
        let permissions = PermissionManager(grants: [extensionID: [.workspaceRead]])
        let records = SDKGrantStore(storeURL: tmp.appendingPathComponent("SDKGrants-tombstone.json"))
        let store = SDKPermissionManagerGrantStore(permissions: permissions, grantRecords: records)
        let name = await store.extensionName(for: extensionID)
        XCTAssertEqual(name, "Tombstone Test App")
        let grants = try await store.grants(for: extensionID)
        guard let readGrant = grants.first(where: { $0.capability == .workspaceRead && $0.isActive() }) else {
            return XCTFail("expected a live workspace.read grant")
        }
        try await store.revoke(readGrant)
        let after = try await store.grants(for: extensionID)
        let tombstone = after.first { $0.capability == .workspaceRead }
        XCTAssertNotNil(tombstone)
        XCTAssertNotNil(tombstone?.revokedAt)
        XCTAssertFalse(tombstone?.isActive() ?? true)
        XCTAssertEqual(tombstone?.packageDigest, digest)
        let nameAfter = await store.extensionName(for: extensionID)
        XCTAssertEqual(nameAfter, "Tombstone Test App")
        try await SDKExtensionRegistry.shared.removeInstallRecord(extensionID: extensionID, version: "1.0.0-test")
    }

    func testAssistAccessMapping() {
        let app = SDKStudioAssistAccessApplication(
            extensionID: "com.example.app", displayName: "App", keyID: nil, variant: .newApplication,
            usageDescription: "We use Assist to summarize code for the user.",
            hasOwnUI: false, ownUIDescription: nil, usesThirdPartyModels: false, thirdPartyModels: nil,
            dataLeavesDevice: false, dataDestination: nil, contactEmail: "dev@example.com")
        XCTAssertEqual(app.sdkVariant, .assistSDKUI)
        let short = SDKStudioAssistAccessApplication(
            extensionID: "com.example.app", displayName: "App", keyID: nil, variant: .newApplication,
            usageDescription: String(repeating: "x", count: 39),
            hasOwnUI: false, ownUIDescription: nil, usesThirdPartyModels: false, thirdPartyModels: nil,
            dataLeavesDevice: false, dataDestination: nil, contactEmail: "dev@example.com")
        XCTAssertNotNil(short.validationErrors()["usageDescription"])
        let exact = SDKStudioAssistAccessApplication(
            extensionID: "com.example.app", displayName: "App", keyID: nil, variant: .newApplication,
            usageDescription: String(repeating: "x", count: 40),
            hasOwnUI: false, ownUIDescription: nil, usesThirdPartyModels: false, thirdPartyModels: nil,
            dataLeavesDevice: false, dataDestination: nil, contactEmail: "dev@example.com")
        XCTAssertNil(exact.validationErrors()["usageDescription"])
        let thirdParty = SDKStudioAssistAccessApplication(
            extensionID: "com.example.app", displayName: "App", keyID: nil, variant: .newApplication,
            usageDescription: "We use Assist to summarize code for the user.",
            hasOwnUI: false, ownUIDescription: nil,
            usesThirdPartyModels: true, thirdPartyModels: "openai/gpt-4o, anthropic/claude-sonnet",
            dataLeavesDevice: false, dataDestination: nil, contactEmail: "dev@example.com")
        let keyID = UUID()
        let field = thirdParty.makeField(apiKeyID: keyID)
        XCTAssertEqual(field.apiKeyID, keyID)
        XCTAssertEqual(field.sdkVariant, .assistSDKUI)
        XCTAssertEqual(field.thirdPartyModels, ["openai/gpt-4o", "anthropic/claude-sonnet"])
        XCTAssertEqual(field.contactEmail, "dev@example.com")
    }

    func testExampleManagerPreparesFromTemplate() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let templateURL = repoRoot.appendingPathComponent("sdk/templates/extension-typescript")
        let projectsDir = tmp.appendingPathComponent("Projects")
        let first = try SDKExampleManager.prepareExampleProject(
            templateURL: templateURL, projectsDirectory: projectsDir)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: first.appendingPathComponent("swiftcode.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: first.appendingPathComponent("package.json").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: first.appendingPathComponent("src/index.ts").path))
        let manifest = try JSONDecoder().decode(
            SwiftCodeManifest.self, from: Data(contentsOf: first.appendingPathComponent("swiftcode.json")))
        XCTAssertEqual(manifest.id, SDKExampleManager.exampleID)
        XCTAssertEqual(manifest.id, "com.example.repository-build-extension")
        let second = try SDKExampleManager.prepareExampleProject(
            templateURL: templateURL, projectsDirectory: projectsDir)
        XCTAssertEqual(first, second)
    }

    func testAPIKeyModel() {
        XCTAssertNil(SDKStudioAPIKeyScope(rawValue: ""))
        XCTAssertEqual(SDKStudioAPIKeyScope.appsCreate.rawValue, "apps:create")
        let key = SDKStudioAPIKey(keyPrefix: "sc_dev_live_abc", label: "Test",
                                  scopes: [.appsCreate], expiresAt: Date.distantPast)
        XCTAssertTrue(key.isExpired)
        XCTAssertFalse(key.isRevoked)
        let revoked = SDKStudioAPIKey(keyPrefix: "sc_dev_test_x", label: "Old",
                                      scopes: [.appsPublish], revokedAt: Date())
        XCTAssertTrue(revoked.isRevoked)
    }

    func testAssistAccessValidation() {
        let valid = SDKStudioAssistAccessApplication(
            extensionID: "com.example.app", displayName: "App", keyID: nil, variant: .newApplication,
            usageDescription: "We use Assist to summarize code for the user.",
            hasOwnUI: false, ownUIDescription: nil, usesThirdPartyModels: false, thirdPartyModels: nil,
            dataLeavesDevice: false, dataDestination: nil, contactEmail: "dev@example.com")
        XCTAssertTrue(valid.validationErrors().isEmpty)
        let invalid = SDKStudioAssistAccessApplication(
            extensionID: "", displayName: "", keyID: nil, variant: .newApplication,
            usageDescription: "short", hasOwnUI: true, ownUIDescription: "",
            usesThirdPartyModels: true, thirdPartyModels: nil,
            dataLeavesDevice: true, dataDestination: nil, contactEmail: "not-an-email")
        let errors = invalid.validationErrors()
        XCTAssertNotNil(errors["extensionID"])
        XCTAssertNotNil(errors["displayName"])
        XCTAssertNotNil(errors["usageDescription"])
        XCTAssertNotNil(errors["ownUIDescription"])
        XCTAssertNotNil(errors["thirdPartyModels"])
        XCTAssertNotNil(errors["dataDestination"])
        XCTAssertNotNil(errors["contactEmail"])
    }

    func testUserLogger() {
        let logger = SDKStudioUserLogger()
        logger.info("hello", correlationID: "abc-123")
        logger.warning("careful")
        logger.error("boom")
        XCTAssertEqual(logger.recentEntries().count, 3)
        XCTAssertEqual(logger.entries(matching: "abc-123").count, 1)
        XCTAssertEqual(logger.entries(matching: "HELLO").count, 1, "Search is case-insensitive")
        logger.clear()
        XCTAssertTrue(logger.recentEntries().isEmpty)
    }
}
