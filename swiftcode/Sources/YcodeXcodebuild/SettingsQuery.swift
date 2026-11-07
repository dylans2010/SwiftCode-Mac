import Foundation
import YcodeProject
import YcodeSettings
import YcodeSubprocess

public struct Arena: Equatable, Sendable {
    public var derivedDataPath: String
    public var buildProductsPath: String
    public var buildIntermediatesPath: String

    public static func forContainer(_ c: Container, derivedDataPath: String?, derivedDataRoot root: String) -> Arena {
        if let d = derivedDataPath {
            return Arena(derivedDataPath: d, buildProductsPath: d + "/Build/Products", buildIntermediatesPath: d + "/Build/Intermediates.noindex")
        }
        let folder = root + "/" + DerivedDataName.folder(name: c.name, path: c.url.path)
        return Arena(derivedDataPath: root, buildProductsPath: folder + "/Build/Products", buildIntermediatesPath: folder + "/Build/Intermediates.noindex")
    }

    var json: [String: Any] {
        let projectFolder = URL(fileURLWithPath: buildProductsPath).deletingLastPathComponent().deletingLastPathComponent().path
        return [
            "derivedDataPath": derivedDataPath,
            "buildProductsPath": buildProductsPath,
            "buildIntermediatesPath": buildIntermediatesPath,
            "pchPath": buildIntermediatesPath + "/PrecompiledHeaders",
            "indexRegularBuildProductsPath": projectFolder + "/Index.noindex/Build/Products",
            "indexRegularBuildIntermediatesPath": projectFolder + "/Index.noindex/Build/Intermediates.noindex",
            "indexPCHPath": projectFolder + "/Index.noindex/PrecompiledHeaders",
            "indexDataStoreFolderPath": projectFolder + "/Index.noindex/DataStore",
            "indexEnableDataStore": true,
        ]
    }
}

public enum DerivedDataName {
    public static func hash(_ path: String) -> String {
        let d = MD5.digest(Array(path.utf8))
        func half(_ bytes: ArraySlice<UInt8>) -> String {
            var v = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            var chars = [Character](repeating: "a", count: 14)
            for i in stride(from: 13, through: 0, by: -1) {
                chars[i] = Character(UnicodeScalar(UInt8(97 + v % 26)))
                v /= 26
            }
            return String(chars)
        }
        return half(d[0..<8]) + half(d[8..<16])
    }

    public static func folder(name: String, path: String) -> String {
        name.replacingOccurrences(of: " ", with: "_") + "-" + hash(path)
    }
}

public struct RunDestination: Equatable, Sendable {
    public var platform: String
    public var sdk: String
    public var sdkVariant: String?
    public var targetArchitecture: String
    public var supportedArchitectures: [String]
    public var disableOnlyActiveArch = false

    public init(platform: String, sdk: String, sdkVariant: String? = nil, targetArchitecture: String, supportedArchitectures: [String]) {
        self.platform = platform
        self.sdk = sdk
        self.sdkVariant = sdkVariant
        self.targetArchitecture = targetArchitecture
        self.supportedArchitectures = supportedArchitectures
    }

    public static func hostMac(architecture: String) -> RunDestination {
        RunDestination(platform: "macosx", sdk: "macosx", sdkVariant: "macos", targetArchitecture: architecture,
                       supportedArchitectures: ["arm64", "x86_64"])
    }

    var json: [String: Any] {
        var d: [String: Any] = ["platform": platform, "sdk": sdk, "targetArchitecture": targetArchitecture,
                                "supportedArchitectures": supportedArchitectures, "disableOnlyActiveArch": disableOnlyActiveArch]
        if let v = sdkVariant { d["sdkVariant"] = v }
        return d
    }
}

public struct BuildParameters: Sendable {
    public var action: String
    public var configuration: String
    public var arena: Arena?
    public var runDestination: RunDestination?
    public var overrides: [(String, String)]
    public var xcconfigPath: String?
    public var synthesized: [(String, String)] = []

    public init(action: String, configuration: String, arena: Arena? = nil, runDestination: RunDestination? = nil,
                overrides: [(String, String)] = [], xcconfigPath: String? = nil) {
        self.action = action
        self.configuration = configuration
        self.arena = arena
        self.runDestination = runDestination
        self.overrides = overrides
        self.xcconfigPath = xcconfigPath
    }

    public var json: [String: Any] {
        var table: [String: String] = [:]
        for (k, v) in overrides { table[k] = v }
        var overridesObject: [String: Any] = ["commandLine": ["table": table]]
        if let x = xcconfigPath { overridesObject["commandLineConfigPath"] = x }
        if !synthesized.isEmpty {
            var s: [String: String] = [:]
            for (k, v) in synthesized { s[k] = v }
            overridesObject["synthesized"] = ["table": s]
        }
        var d: [String: Any] = ["action": action, "configurationName": configuration, "overrides": overridesObject]
        if let a = arena { d["arenaInfo"] = a.json }
        if let r = runDestination {
            d["activeRunDestination"] = r.json
            d["activeArchitecture"] = r.targetArchitecture
        }
        return d
    }
}

public struct SettingsTarget {
    public var project: LoadedProject
    public var target: PBXObject
    public var name: String { target.string("name") ?? "" }
}

public protocol SettingsProvider {
    func settings(container: Container, targets: [SettingsTarget], parameters: BuildParameters) throws -> [[String: String]]
    func settings(pif: URL, guids: [String], parameters: BuildParameters) throws -> [[String: String]]
}

extension SettingsProvider {
    public func settings(pif: URL, guids: [String], parameters: BuildParameters) throws -> [[String: String]] {
        throw SettingsError(description: "this settings provider cannot evaluate a Swift package's build description")
    }
}

public struct SettingsError: Error, CustomStringConvertible {
    public var description: String
}

public struct SwiftBuildSettingsProvider: SettingsProvider {
    public var helper: String
    public var scratch: URL

    public init(helper: String, scratch: URL = FileManager.default.temporaryDirectory) {
        self.helper = helper
        self.scratch = scratch
    }

    public static func locate(environment: [String: String], executableDirectory: String?) -> String? {
        let fm = FileManager.default
        if let p = environment["SWIFTCODE_SWB"], fm.isExecutableFile(atPath: p) { return p }
        for dir in (environment["PATH"] ?? "").split(separator: ":") where fm.isExecutableFile(atPath: "\(dir)/swiftcode-swb") {
            return "\(dir)/swiftcode-swb"
        }
        if let d = executableDirectory, fm.isExecutableFile(atPath: d + "/swiftcode-swb") { return d + "/swiftcode-swb" }
        return nil
    }

    public func settings(container: Container, targets: [SettingsTarget], parameters: BuildParameters) throws -> [[String: String]] {
        let pif = XcodePIF(container: container)
        let work = scratch.appendingPathComponent("swiftcodebuild-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let pifURL = work.appendingPathComponent("workspace.pif.json")
        try pif.serialized().write(to: pifURL)
        return try settings(pif: pifURL, guids: targets.map { pif.targetGUID($0.project, $0.target) }, parameters: parameters, work: work)
    }

    public func settings(pif pifURL: URL, guids: [String], parameters: BuildParameters) throws -> [[String: String]] {
        let work = scratch.appendingPathComponent("swiftcodebuild-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        return try settings(pif: pifURL, guids: guids, parameters: parameters, work: work)
    }

    func settings(pif pifURL: URL, guids: [String], parameters: BuildParameters, work: URL) throws -> [[String: String]] {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let request: [String: Any] = [
            "pif": pifURL.path,
            "parameters": parameters.json,
            "levels": guids.map { ["target": $0] },
        ]
        let requestURL = work.appendingPathComponent("request.json")
        try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]).write(to: requestURL)
        MainThreadGuard.blockingCall("swiftcode-swb settings")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: helper)
        p.arguments = ["settings", requestURL.path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = reply["settings"] as? [[String: String]] else {
            throw SettingsError(description: "the settings helper failed: " + String(decoding: errData, as: UTF8.self))
        }
        return list
    }
}

public struct ResolverSettingsProvider: SettingsProvider {
    public var developerDirectory: String?
    public init(developerDirectory: String?) { self.developerDirectory = developerDirectory }

    public func settings(container: Container, targets: [SettingsTarget], parameters: BuildParameters) throws -> [[String: String]] {
        let catalog = developerDirectory.map { SDKCatalog(developerDirectory: $0) }
        return try targets.map { t in
            var b = ProjectSettingsBuilder(proj: t.project.proj, xcodeprojURL: t.project.url)
            b.developerDirectory = developerDirectory
            if let catalog { b.sdkLookup = { catalog.lookup($0) } }
            var o: [String: String] = [:]
            for (k, v) in parameters.overrides { o[k] = v }
            b.overrides = o
            let resolved = try b.resolve(target: t.name, configuration: parameters.configuration)
            var all = resolved.settings.all()
            all["ACTION"] = parameters.action
            return all
        }
    }
}
