import XCTest
@testable import YcodeExtensions

final class CapabilityTests: XCTestCase {
    func testDenyByDefault() {
        let permissions = PermissionManager(grants: [:])
        XCTAssertFalse(permissions.isGranted(extensionId: "acme.sample", capability: .workspaceRead))
        XCTAssertThrowsError(try permissions.check(extensionId: "acme.sample", capability: .workspaceRead)) { error in
            XCTAssertEqual(error.localizedDescription,
                           "Permission denied: Read workspace files. Grant it in Extensions > Permissions.")
        }
    }

    func testGrantAndRevoke() {
        let permissions = PermissionManager(grants: [:])
        permissions.grant(extensionId: "acme.sample", capability: .workspaceRead)
        XCTAssertTrue(permissions.isGranted(extensionId: "acme.sample", capability: .workspaceRead))
        XCTAssertNoThrow(try permissions.check(extensionId: "acme.sample", capability: .workspaceRead))
        XCTAssertEqual(permissions.grantedCapabilities(for: "acme.sample"), [.workspaceRead])
        permissions.revoke(extensionId: "acme.sample", capability: .workspaceRead)
        XCTAssertFalse(permissions.isGranted(extensionId: "acme.sample", capability: .workspaceRead))
        permissions.grant(extensionId: "acme.sample", capability: .network)
        permissions.revokeAll(for: "acme.sample")
        XCTAssertTrue(permissions.grantedCapabilities(for: "acme.sample").isEmpty)
    }

    func testRequestWithoutPromptHandlerIsDenial() async {
        let permissions = PermissionManager(grants: [:])
        let granted = await permissions.request(extensionId: "acme.sample", capability: .workspaceWrite,
                                                reason: "Write files.")
        XCTAssertFalse(granted)
        XCTAssertFalse(permissions.isGranted(extensionId: "acme.sample", capability: .workspaceWrite))
    }

    func testRequestWithApprovingHandlerGrants() async {
        let permissions = PermissionManager(grants: [:])
        permissions.promptHandler = { request in
            XCTAssertEqual(request.extensionId, "acme.sample")
            XCTAssertEqual(request.capability, .workspaceWrite)
            return true
        }
        let granted = await permissions.request(extensionId: "acme.sample", capability: .workspaceWrite,
                                                reason: "Write files.")
        XCTAssertTrue(granted)
        XCTAssertTrue(permissions.isGranted(extensionId: "acme.sample", capability: .workspaceWrite))
    }

    func testRequestWithDenyingHandlerDoesNotGrant() async {
        let permissions = PermissionManager(grants: [:])
        permissions.promptHandler = { _ in false }
        let granted = await permissions.request(extensionId: "acme.sample", capability: .network, reason: "Net.")
        XCTAssertFalse(granted)
    }

    func testRequestAlreadyGrantedReturnsTrueImmediately() async {
        let permissions = PermissionManager(grants: ["acme.sample": [.terminal]])
        permissions.promptHandler = { _ in
            XCTFail("Prompt handler must not be called for an already-granted capability.")
            return false
        }
        XCTAssertTrue(await permissions.request(extensionId: "acme.sample", capability: .terminal, reason: "x"))
    }

    func testSDKCapabilityRiskAndGrantability() {
        XCTAssertEqual(SDKCapabilityID.projectRead.riskLevel, "low")
        XCTAssertEqual(SDKCapabilityID.workspaceRead.riskLevel, "medium")
        XCTAssertEqual(SDKCapabilityID.securityUseValue.riskLevel, "high")
        XCTAssertEqual(SDKCapabilityID.allCases.count, 35)
        XCTAssertFalse(SDKCapabilityID.assistInvoke.isGrantable)
        XCTAssertTrue(SDKCapabilityID.workspaceRead.isGrantable)
    }

    func testSDKToV2Mapping() {
        XCTAssertEqual(ExtensionCapability.v2Capabilities(for: .workspaceRead), [.workspaceRead])
        XCTAssertEqual(ExtensionCapability.v2Capabilities(for: .networkRequest), [.network])
        XCTAssertEqual(ExtensionCapability.v2Capabilities(for: .terminalSandbox), [.terminal, .process])
        XCTAssertEqual(ExtensionCapability.v2Capabilities(for: .assistInvoke), [.assistTools])
        XCTAssertEqual(ExtensionCapability.v2Capabilities(for: .credentialsUse), [.secrets])
        XCTAssertEqual(ExtensionCapability.allCases.count, 12)
    }

    func testGrantsPersistWith0600Mode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YcodeExtensionsGrants-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ExtensionStorage(root: root)
        let permissions = PermissionManager(storage: storage)
        permissions.grant(extensionId: "acme.sample", capability: .build)
        let mode = try FileManager.default.attributesOfItem(atPath: storage.grantsFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        let reloaded = PermissionManager(storage: storage)
        XCTAssertTrue(reloaded.isGranted(extensionId: "acme.sample", capability: .build))
    }
}

final class DependencyTests: XCTestCase {
    private func manifest(id: String, dependencies: [String]) -> VSCodeManifest {
        let dict: [String: Any] = [
            "name": id.split(separator: ".").last.map(String.init) ?? id,
            "publisher": id.split(separator: ".").first.map(String.init) ?? "x",
            "version": "1.0.0",
            "engines": ["vscode": "^1.80.0"],
            "extensionDependencies": dependencies,
        ]
        return try! VSCodeManifestParser.parse(data: try! JSONSerialization.data(withJSONObject: dict))
    }

    func testTopologicalOrderDependenciesFirst() {
        let a = manifest(id: "acme.a", dependencies: ["acme.b"])
        let b = manifest(id: "acme.b", dependencies: [])
        let resolution = DependencyResolver.resolve(requested: [a, b], installedIDs: [],
                                                    manifestsByID: ["acme.a": a, "acme.b": b])
        XCTAssertTrue(resolution.isSatisfied)
        XCTAssertEqual(resolution.installOrder, ["acme.b", "acme.a"])
    }

    func testMissingDependencyReportedOnce() {
        let a = manifest(id: "acme.a", dependencies: ["acme.missing", "acme.missing"])
        let resolution = DependencyResolver.resolve(requested: [a], installedIDs: [],
                                                    manifestsByID: ["acme.a": a])
        XCTAssertFalse(resolution.isSatisfied)
        XCTAssertEqual(resolution.missing, ["acme.missing"])
    }

    func testCycleReported() {
        let a = manifest(id: "acme.a", dependencies: ["acme.b"])
        let b = manifest(id: "acme.b", dependencies: ["acme.a"])
        let resolution = DependencyResolver.resolve(requested: [a], installedIDs: [],
                                                    manifestsByID: ["acme.a": a, "acme.b": b])
        XCTAssertFalse(resolution.isSatisfied)
        XCTAssertFalse(resolution.cycles.isEmpty)
    }

    func testDisabledDependencyCountsAsMissing() {
        let metadata = ExtensionMetadata(publisher: "acme", name: "a", version: "1.0.0",
                                         displayName: "A", description: "")
        let dep = InstalledExtension(metadata: ExtensionMetadata(publisher: "acme", name: "dep", version: "1.0.0",
                                                                 displayName: "Dep", description: ""),
                                     isEnabled: false, installPath: "/tmp")
        let installed = InstalledExtension(metadata: metadata, installPath: "/tmp",
                                           dependencies: ["acme.dep"])
        XCTAssertEqual(DependencyResolver.missingDependencies(for: installed,
                                                              installedByID: ["acme.dep": dep]),
                       ["acme.dep"])
    }
}

final class RPCTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let request = RPCRequest(id: "acme.sample:1", method: "activate",
                                 params: .object(["extensionId": .string("acme.sample")]))
        let data = try ExtensionRPC.encodeRequest(request)
        XCTAssertTrue(data.last == UInt8(ascii: "\n"))
        let decoded = try ExtensionRPC.decodeRequest(from: Data(data.dropLast()), fromHost: false)
        XCTAssertEqual(decoded.id, "acme.sample:1")
        XCTAssertEqual(decoded.method, "activate")
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testResponseRoundTrip() throws {
        let response = RPCResponse(id: "acme.sample:1", result: .string("ok"))
        let data = try ExtensionRPC.encodeResponse(response)
        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        XCTAssertEqual(decoded.result, .string("ok"))
    }

    func testDisallowedMethodIsRejected() {
        let request = RPCRequest(id: "host-1", method: "activate")
        let data = try! ExtensionRPC.encodeRequest(request)
        // "activate" is a SwiftCode->host method; from the host it is disallowed.
        XCTAssertThrowsError(try ExtensionRPC.decodeRequest(from: Data(data.dropLast()), fromHost: true))
        // And a host method is disallowed in the SwiftCode direction.
        let hostRequest = RPCRequest(id: "x", method: "host.log")
        let hostData = try! ExtensionRPC.encodeRequest(hostRequest)
        XCTAssertThrowsError(try ExtensionRPC.decodeRequest(from: Data(hostData.dropLast()), fromHost: false))
    }

    func testOversizeLineIsRejected() {
        let big = Data(repeating: UInt8(ascii: "a"), count: 1024 * 1024 + 1)
        XCTAssertThrowsError(try ExtensionRPC.decodeRequest(from: big, fromHost: true))
    }

    func testWrongProtocolVersionIsRejected() throws {
        let json = #"{"jsonrpc":"2.0","protocolVersion":2,"id":"x","method":"host.log"}"#
        XCTAssertThrowsError(try ExtensionRPC.decodeRequest(from: Data(json.utf8), fromHost: true))
    }

    func testAllowedMethodSets() {
        XCTAssertEqual(ExtensionRPC.allowedHostMethods.count, 20)
        XCTAssertEqual(ExtensionRPC.allowedHostMethodsSwiftCode.count, 6)
        XCTAssertTrue(ExtensionRPC.allowedHostMethods.contains("host.applyEdit"))
        XCTAssertTrue(ExtensionRPC.allowedHostMethodsSwiftCode.contains("executeCommand"))
    }

    func testJSONValueRoundTrip() throws {
        let value: JSONValue = .object(["a": .int(1), "b": .array([.string("x"), .bool(true), .null])])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }
}

final class AssistBridgeTests: XCTestCase {
    func testToolIDSanitisation() {
        XCTAssertEqual(AssistBridge.toolId(for: "acme.sample", command: "acme.hello"),
                       "extv2.acme.sample.acme.hello")
        XCTAssertEqual(AssistBridge.toolId(for: "acme.sample", command: "do-thing_now"),
                       "extv2.acme.sample.do_thing_now")
    }

    func testDescriptorDefaults() {
        let command = ExtensionContributionCommand(command: "acme.hello", title: "Hello")
        let descriptor = AssistBridge.descriptor(for: command, extensionId: "acme.sample")
        XCTAssertEqual(descriptor.toolId, "extv2.acme.sample.acme.hello")
        XCTAssertEqual(descriptor.name, "Hello")
        XCTAssertEqual(descriptor.description, "Extension command 'acme.hello' from acme.sample.")
        XCTAssertTrue(descriptor.parameters.isEmpty)
        XCTAssertTrue(descriptor.isReadOnly)
    }

    @MainActor
    func testRegisterRequiresAssistToolsGrant() {
        let permissions = PermissionManager(grants: [:])
        let command = ExtensionContributionCommand(command: "acme.hello", title: "Hello")
        let descriptor = AssistBridge.descriptor(for: command, extensionId: "acme.sample")
        XCTAssertFalse(AssistBridge.register(descriptor, permissions: permissions))
        permissions.grant(extensionId: "acme.sample", capability: .assistTools)
        XCTAssertTrue(AssistBridge.register(descriptor, permissions: permissions))
    }

    func testDescriptorValidation() throws {
        let descriptor = AssistCapabilityDescriptor(
            toolId: "extv2.acme.sample.acme.hello", name: "Hello",
            description: "d", parameters: ["count": "number", "label": "string"],
            requiredParameters: ["label"], extensionId: "acme.sample", command: "acme.hello")
        XCTAssertThrowsError(try descriptor.validate(input: [:]))
        XCTAssertThrowsError(try descriptor.validate(input: ["label": "x", "count": "not-a-number"]))
        XCTAssertNoThrow(try descriptor.validate(input: ["label": "x", "count": NSNumber(value: 3)]))
        XCTAssertNoThrow(try descriptor.validate(input: ["label": "x", "count": 3, "unknown": 1]))
    }
}
