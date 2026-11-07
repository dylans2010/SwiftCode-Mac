import Foundation
import SwiftBuild
import SwiftCodeRelease
import SwiftCodeSigning

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swiftcode-swb: \(message)\n".utf8))
    exit(2)
}

struct SettingsRequest: Decodable {
    var pif: String
    var parameters: SWBBuildParameters
    var levels: [[String: String]]
}

struct BuildRequestFile: Decodable {
    var pif: String
    var parameters: SWBBuildParameters
    var targets: [String]?
    var targetNames: [String]?
    var containerPath: String?
    var parallel: Bool?
    var implicitDependencies: Bool?
    var hideShellScriptEnvironment: Bool?
    var continueAfterErrors: Bool?
    var command: String?
    var locationStyle: String?
    var schemeCommand: String?
    var debuggable: Bool?
}

func decode<T: Decodable>(_ type: T.Type, _ path: String) -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: path))) } catch {
        fail("cannot read request \(path): \(error)")
    }
}

func withSession<R>(pif: String, _ body: (SWBBuildServiceSession, [String]) async throws -> R) async -> R {
    let service: SWBBuildService
    do { service = try await SWBBuildService() } catch { fail("cannot start the build service: \(error)") }
    let toolchain = hostSwiftToolchain()
    let (result, sessionDiagnostics) = if let toolchain {
        await service.createSession(name: pif, swiftToolchainPath: toolchain, resourceSearchPaths: [], cachePath: nil,
                                    inferiorProductsPath: nil, environment: nil)
    } else {
        await service.createSession(name: pif, cachePath: nil, inferiorProductsPath: nil, environment: nil)
    }
    let session: SWBBuildServiceSession
    switch result {
    case .success(let s): session = s
    case .failure(let e):
        var message = "cannot create a session: \(e)"
        for d in sessionDiagnostics { message += "\n  \(d.kind): \(d.message)" }
        #if !os(macOS)
        if toolchain == nil {
            message += "\n  No Swift toolchain was found: put `swift` on PATH, or set SWIFTCODE_SWIFT_TOOLCHAIN to the folder that holds usr/bin/swift."
        }
        #endif
        fail(message)
    }
    do {
        try await session.loadWorkspace(containerPath: pif)
        _ = try await session.workspaceInfo()
        try await session.setSystemInfo(.default())
        try await session.setUserInfo(.default)
        let r = try await body(session, sessionDiagnostics.map { "\($0.kind): \($0.message)" })
        try? await session.close()
        await service.close()
        return r
    } catch {
        try? await session.close()
        fail("\(error)")
    }
}

func hostSwiftToolchain() -> String? {
    #if os(macOS)
    nil
    #else
    SwiftToolchain.locate()
    #endif
}

func settings(_ path: String) async {
    let request = decode(SettingsRequest.self, path)
    await withSession(pif: request.pif) { session, initial in
        var diagnostics = initial
        var out: [[String: String]] = []
        for level in request.levels {
            let l: SWBMacroEvaluationLevel
            if let g = level["target"] { l = .target(g) } else if let g = level["project"] { l = .project(g) } else { l = .defaults }
            do {
                out.append(try await session.allExportedMacroNamesAndValues(level: l, buildParameters: request.parameters))
            } catch {
                diagnostics.append("error: \(error)")
                out.append([:])
            }
        }
        let reply: [String: Any] = ["settings": out, "diagnostics": diagnostics]
        let data = try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

final class SigningDelegate: SWBPlanningOperationDelegate, Sendable {
    let debuggable: Bool
    let environment: SigningEnvironment
    let targetNames: [String: String]

    init(debuggable: Bool = true, targetNames: [String: String] = [:]) {
        self.debuggable = debuggable
        self.targetNames = targetNames
        let user = SigningEnvironment.user()
        let identities = Cache(user.identities)
        let profiles = Cache(user.profiles)
        environment = SigningEnvironment(identities: { identities.value }, profiles: { profiles.value })
    }

    final class Cache<T: Sendable>: @unchecked Sendable {
        let lock = NSLock()
        let make: @Sendable () -> T
        var stored: T?
        init(_ make: @escaping @Sendable () -> T) { self.make = make }
        var value: T {
            lock.lock()
            defer { lock.unlock() }
            if let stored { return stored }
            let v = make()
            stored = v
            return v
        }
    }

    static func value(_ v: SWBPropertyListItem) -> EntitlementValue {
        switch v {
        case .plBool(let b): .bool(b)
        case .plInt(let i): .integer(i)
        case .plString(let s): .string(s)
        case .plData(let d): .data(Data(d))
        case .plDate(let d): .date(d)
        case .plDouble(let d): .real(d)
        case .plArray(let a): .array(a.map(value))
        case .plDict(let d): .dictionary(d.mapValues(value))
        }
    }

    static func item(_ v: EntitlementValue) -> SWBPropertyListItem {
        switch v {
        case .bool(let b): .plBool(b)
        case .integer(let i): .plInt(i)
        case .string(let s): .plString(s)
        case .data(let d): .plData([UInt8](d))
        case .date(let d): .plDate(d)
        case .real(let d): .plDouble(d)
        case .array(let a): .plArray(a.map(item))
        case .dictionary(let d): .plDict(d.mapValues(item))
        }
    }

    func provisioningTaskInputs(targetGUID: String, provisioningSourceData s: SWBProvisioningTaskInputsSourceData) async -> SWBProvisioningTaskInputs {
        let support: SigningRequest.ProfileSupport = switch s.provisioningProfileSupport {
        case .unsupported: .unsupported
        case .optional: .optional
        case .required: .required
        }
        let request = SigningRequest(
            targetName: targetNames[targetGUID] ?? targetGUID,
            identity: s.signingCertificateIdentifier,
            style: s.provisioningStyle == .automatic ? .automatic : .manual,
            team: s.teamID, bundleIdentifier: s.bundleIdentifier,
            profileSpecifier: s.provisioningProfileSpecifier, profileUUID: s.provisioningProfileUUID, profileSupport: support,
            productTypeEntitlements: s.productTypeEntitlements.mapValues(Self.value),
            projectEntitlements: s.projectEntitlements?.mapValues(Self.value),
            sdk: s.sdkRoot, sdkVariant: s.sdkVariant, supportsEntitlements: s.supportsEntitlements,
            productType: s.productTypeIdentifier, signingRequiresTeam: s.signingRequiresTeam, debuggable: debuggable)
        let r = ProvisioningResolver.resolve(request, environment: environment)
        guard r.identityHash != nil else { return SWBProvisioningTaskInputs() }
        return SWBProvisioningTaskInputs(
            identityHash: r.identityHash, identityName: r.identityName,
            profileName: r.profile?.name, profileUUID: r.profile?.uuid, profilePath: r.profile?.path,
            signedEntitlements: r.signedEntitlements.mapValues(Self.item),
            simulatedEntitlements: r.simulatedEntitlements.mapValues(Self.item),
            appIdentifierPrefix: r.appIdentifierPrefix, teamIdentifierPrefix: r.teamIdentifierPrefix,
            errors: r.errors.map { ["description": $0] }, warnings: r.warnings)
    }

    func executeExternalTool(commandLine: [String], workingDirectory: String?, environment: [String: String]) async throws -> SWBExternalToolResult {
        .deferred
    }
}

func build(_ path: String) async -> Int32 {
    let file = decode(BuildRequestFile.self, path)
    return await withSession(pif: file.pif) { session, _ in
        var request = SWBBuildRequest()
        request.parameters = file.parameters
        var guids = file.targets ?? []
        let infos = try await session.workspaceInfo().targetInfos
        if let names = file.targetNames {
            for n in names {
                guard let t = infos.first(where: { $0.targetName == n }) else { fail("no target named \(n)") }
                guids.append(t.guid)
            }
        }
        request.configuredTargets = guids.map { SWBConfiguredTarget(guid: $0, parameters: file.parameters) }
        request.useParallelTargets = file.parallel ?? true
        request.useImplicitDependencies = file.implicitDependencies ?? true
        request.hideShellScriptEnvironment = file.hideShellScriptEnvironment ?? false
        request.continueBuildingAfterErrors = file.continueAfterErrors ?? false
        request.showNonLoggedProgress = true
        request.containerPath = file.containerPath
        if let c = file.schemeCommand { request.schemeCommand = SWBSchemeCommand(rawValue: c) ?? .launch }
        if file.command == "cleanBuildFolder" {
            request.buildCommand = .cleanBuildFolder(style: file.locationStyle == "legacy" ? .legacy : .regular)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let operation = try await session.createBuildOperation(request: request, delegate: SigningDelegate(debuggable: file.debuggable ?? true, targetNames: Dictionary(infos.map { ($0.guid, $0.targetName) }) { a, _ in a }))
        var ok = false
        for try await event in try await operation.start() {
            if case .buildCompleted(let info) = event { ok = info.result == .ok }
            var line = try encoder.encode(event)
            line.append(0x0A)
            FileHandle.standardOutput.write(line)
        }
        await operation.waitForCompletion()
        return ok ? 0 : 1
    }
}

SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-swb")
let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: swiftcode-swb settings|build <request.json>\n".utf8))
    exit(2)
}
switch args[1] {
case "settings": await settings(args[2])
case "build": exit(await build(args[2]))
default:
    FileHandle.standardError.write(Data("usage: swiftcode-swb settings|build <request.json>\n".utf8))
    exit(2)
}
