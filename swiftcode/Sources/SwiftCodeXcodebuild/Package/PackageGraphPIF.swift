import Foundation
import SwiftCodeBuild
import SwiftCodeProject
import SwiftCodeSubprocess

public struct PackageGraphPIF: @unchecked Sendable {
    public struct Product: Equatable, Sendable {
        public var name: String
        public var guid: String
        public var targetType: String
        public var productType: String

        public var isDynamic: Bool {
            productType == "com.apple.product-type.library.dynamic" || productType == "com.apple.product-type.framework"
        }
    }

    public struct Package: Equatable, Sendable {
        public var identity: String
        public var directory: String
        public var projectGUID: String
        public var products: [String: Product]
        public var pluginTargets: [String: String] = [:]
    }

    public var packages: [Package] = []
    public var objects: [[String: Any]] = []
    public var projectSignatures: [String] = []
    public var warnings: [String] = []
    public var pluginOutputs: [String: ProjectPlugins.TargetOutputs] = [:]

    public init() {}

    public func package(identity: String) -> Package? { packages.first { $0.identity == identity } }

    public func product(_ name: String, identity: String?) -> Product? {
        if let identity { return package(identity: identity)?.products[name] }
        return packages.lazy.compactMap { $0.products[name] }.first
    }

    public var dynamicProductGUIDs: Set<String> {
        Set(packages.flatMap { $0.products.values.filter(\.isDynamic).map(\.guid) })
    }

    public private(set) var hostToolPrefixes: [String] = []

    public func relocated(_ s: String) -> String {
        var out = s
        for p in hostToolPrefixes where out.contains(p) { out = out.replacingOccurrences(of: p, with: "$(BUILD_DIR)/$(CONFIGURATION)") }
        return out
    }

    public mutating func relocateHostTools(scratchDirectory: String) {
        var prefixes: [String] = []
        for base in Set([scratchDirectory, URL(fileURLWithPath: scratchDirectory).resolvingSymlinksInPath().path,
                         URL(fileURLWithPath: scratchDirectory).standardizedFileURL.path]) {
            for c in ["Debug", "Release"] { prefixes.append(base + "/out/Products/" + c) }
        }
        prefixes.sort { $0.count > $1.count }
        hostToolPrefixes = prefixes
        func rewrite(_ v: Any) -> Any {
            if let s = v as? String {
                var out = s
                for p in prefixes where out.contains(p) { out = out.replacingOccurrences(of: p, with: "$(BUILD_DIR)/$(CONFIGURATION)") }
                return out
            }
            if let a = v as? [Any] { return a.map(rewrite) }
            if let d = v as? [String: Any] { return d.mapValues(rewrite) }
            return v
        }
        var renamed: [String: String] = [:]
        for i in objects.indices {
            guard var c = objects[i]["contents"] as? [String: Any], let tasks = c["customTasks"] as? [Any], !tasks.isEmpty,
                  let signature = objects[i]["signature"] as? String else { continue }
            let rewritten = rewrite(tasks)
            c["customTasks"] = rewritten
            objects[i]["contents"] = c
            let text = (try? JSONSerialization.data(withJSONObject: rewritten, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let newSignature = signature + "-swiftcode-" + MD5.hex(text)
            objects[i]["signature"] = newSignature
            renamed[signature] = newSignature
        }
        guard !renamed.isEmpty else { return }
        for i in objects.indices where objects[i]["type"] as? String == "project" {
            guard var c = objects[i]["contents"] as? [String: Any], let targets = c["targets"] as? [String] else { continue }
            c["targets"] = targets.map { renamed[$0] ?? $0 }
            objects[i]["contents"] = c
            if targets.contains(where: { renamed[$0] != nil }), let s = objects[i]["signature"] as? String {
                let newSignature = s + "-swiftcode-" + MD5.hex(targets.map { renamed[$0] ?? $0 }.joined(separator: ","))
                objects[i]["signature"] = newSignature
                if let j = projectSignatures.firstIndex(of: s) { projectSignatures[j] = newSignature }
            }
        }
    }

    public static func parse(_ data: Data, rootDirectory: String) throws -> PackageGraphPIF {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PIFGenerator.GenerationError.unsupported("swift package dump-pif printed no PIF")
        }
        let root = URL(fileURLWithPath: rootDirectory).standardizedFileURL.path
        var targetsBySignature: [String: [String: Any]] = [:]
        for o in list where o["type"] as? String == "target" {
            if let s = o["signature"] as? String { targetsBySignature[s] = o }
        }
        var out = PackageGraphPIF()
        for o in list where o["type"] as? String == "project" {
            guard let c = o["contents"] as? [String: Any], let signature = o["signature"] as? String else { continue }
            let dir = URL(fileURLWithPath: c["projectDirectory"] as? String ?? "").standardizedFileURL.path
            let targetSignatures = c["targets"] as? [String] ?? []
            let targetNames = targetSignatures.compactMap { (targetsBySignature[$0]?["contents"] as? [String: Any])?["name"] as? String }
            let isAggregate = c["guid"] as? String == "AGGREGATE"
                || (!targetNames.isEmpty && targetNames.allSatisfy { $0 == "AllIncludingTests" || $0 == "AllExcludingTests" })
            if dir == root || isAggregate { continue }
            var package = Package(identity: URL(fileURLWithPath: dir).lastPathComponent.lowercased(), directory: dir,
                                  projectGUID: c["guid"] as? String ?? "", products: [:])
            out.objects.append(o)
            out.projectSignatures.append(signature)
            for s in targetSignatures {
                guard let t = targetsBySignature[s] else { continue }
                out.objects.append(t)
                guard let tc = t["contents"] as? [String: Any], let name = tc["name"] as? String, let guid = tc["guid"] as? String else { continue }
                if tc["productTypeIdentifier"] as? String == "com.apple.product-type.tool.host-build", package.pluginTargets[name] == nil {
                    package.pluginTargets[name] = guid
                }
                guard name.hasSuffix("-product") else { continue }
                let type = tc["type"] as? String ?? "standard"
                if type == "aggregate" { continue }
                let product = String(name.dropLast("-product".count))
                package.products[product] = Product(name: product, guid: guid, targetType: type,
                                                    productType: tc["productTypeIdentifier"] as? String ?? "")
            }
            out.packages.append(package)
        }
        return out
    }
}

public struct PackageGraphLoader: Sendable {
    public var container: Container
    public var sourcePackagesDirectory: URL
    public var swift: String
    public var resolveMissingPins = true

    public init(container: Container, sourcePackagesDirectory: URL, swift: String = PackageGraphLoader.defaultSwift()) {
        self.container = container
        self.sourcePackagesDirectory = sourcePackagesDirectory
        self.swift = swift
    }

    public static func defaultSwift(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var candidates: [String] = []
        if let dev = environment["DEVELOPER_DIR"] { candidates.append(dev + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift") }
        for dir in (environment["PATH"] ?? "/usr/bin").split(separator: ":") { candidates.append("\(dir)/swift") }
        candidates.append("/usr/bin/swift")
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/swift"
    }

    public static func defaultSourcePackages(for url: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        var h: UInt64 = 1469598103934665603
        for b in url.standardizedFileURL.path.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        let name = url.deletingPathExtension().lastPathComponent + "-" + String(h, radix: 36)
        return caches.appendingPathComponent("SwiftCode/SourcePackages/\(name)")
    }

    public struct Reference: Equatable, Sendable {
        public var local: String?
        public var remote: String?
        public var identity: String {
            if let local { return URL(fileURLWithPath: local).lastPathComponent.lowercased() }
            return PackageResolver.identity(of: remote ?? "")
        }
    }

    public var references: [Reference] {
        var out: [Reference] = []
        for p in container.projects {
            for r in LocalPackages.references(in: p) {
                let ref = Reference(local: r.local, remote: r.remote)
                if !out.contains(ref) { out.append(ref) }
            }
        }
        return out
    }

    public var usesPackages: Bool { !references.isEmpty }

    var resolvedFile: URL { container.workspacePath.appendingPathComponent("xcshareddata/swiftpm/Package.resolved") }

    public func pinnedCheckouts() throws -> [PackageResolver.Pin] {
        let roots: [(url: String, requirement: SwiftPackageRequirement)] = {
            var out: [(url: String, requirement: SwiftPackageRequirement)] = []
            for p in container.projects {
                for r in PackageResolver.roots(of: p.proj) where !out.contains(where: { $0.url == r.url }) { out.append(r) }
            }
            return out
        }()
        guard !roots.isEmpty else { return [] }
        let resolver = PackageResolver(checkoutsDirectory: sourcePackagesDirectory.appendingPathComponent("checkouts"))
        var pins = resolver.readResolvedFile(resolvedFile) ?? []
        let pinned = Set(pins.map(\.identity))
        if roots.contains(where: { !pinned.contains(PackageResolver.identity(of: $0.url)) }) {
            guard resolveMissingPins else {
                throw PIFGenerator.GenerationError.unsupported("packages are not resolved: run Resolve Package Versions")
            }
            pins = try resolver.resolveGraph(roots)
            try FileManager.default.createDirectory(at: resolvedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PackageResolver.resolvedFileV3(pins, originHash: PackageResolver.originHash(rootLocations: roots.map(\.url)))
                .write(to: resolvedFile, options: .atomic)
        }
        for p in pins { try resolver.checkout(identity: p.identity, location: p.location, revision: p.revision) }
        return pins
    }

    public static func rootManifest(packageDirectories: [String]) -> String {
        func literal(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var text = """
        // swift-tools-version: 5.9
        // Generated by SwiftCode: the packages of one project or workspace, for
        // `swift package dump-pif` (specs/ide/build-pif.md). Do not edit.
        import PackageDescription

        let package = Package(
            name: "swiftcode-package-graph",
            dependencies: [

        """
        for d in packageDirectories { text += "        .package(path: \(literal(d))),\n" }
        text += "    ]\n)\n"
        return text
    }

    public func packageDirectories(pins: [PackageResolver.Pin]) -> [String] {
        var out: [String] = []
        var identities = Set<String>()
        for r in references {
            guard let local = r.local, identities.insert(r.identity).inserted else { continue }
            out.append(URL(fileURLWithPath: local).standardizedFileURL.path)
        }
        for p in pins where identities.insert(p.identity).inserted { out.append(p.checkout.standardizedFileURL.path) }
        return out
    }

    public func load() throws -> PackageGraphPIF? {
        guard usesPackages else { return nil }
        let dirs = packageDirectories(pins: try pinnedCheckouts())
        for d in dirs where !FileManager.default.fileExists(atPath: d + "/Package.swift") {
            throw PIFGenerator.GenerationError.unsupported("no Package.swift in \(d)")
        }
        let root = sourcePackagesDirectory.appendingPathComponent("swiftcode-package-graph")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = Data(Self.rootManifest(packageDirectories: dirs).utf8)
        let manifestURL = root.appendingPathComponent("Package.swift")
        if FileManager.default.contents(atPath: manifestURL.path) != manifest { try manifest.write(to: manifestURL, options: .atomic) }
        let scratch = sourcePackagesDirectory.appendingPathComponent("swiftcode-package-graph-build")
        let (status, out, err) = Self.run(swift, ["package", "--package-path", root.path, "--scratch-path", scratch.path, "dump-pif"])
        guard status == 0 else {
            let message = err.split(separator: "\n").filter { $0.contains("error:") }.joined(separator: "\n")
            throw PIFGenerator.GenerationError.unsupported("swift package dump-pif failed: \(message.isEmpty ? err : message)")
        }
        var graph = try PackageGraphPIF.parse(out, rootDirectory: root.path)
        if container.projects.contains(where: { p in p.targets.contains { !ProjectPlugins.applied($0, in: p.proj).isEmpty } }) {
            graph.pluginOutputs = try ProjectPlugins.run(container: container, graph: graph, sourcePackages: sourcePackagesDirectory,
                                                         scratch: scratch, toolchain: try ProjectPlugins.Toolchain.locate(swift: swift))
        }
        graph.relocateHostTools(scratchDirectory: scratch.path)
        let missing = Self.missingProducts(container, graph)
        if !missing.isEmpty {
            throw PIFGenerator.GenerationError.unsupported(missing.map { "Missing package product '\($0)'" }.joined(separator: "\n"))
        }
        graph.warnings = err.split(separator: "\n").map(String.init).filter { line in
            line.contains("warning:") && !line.contains("'swiftcode-package-graph'") && !line.contains("Conflicting identity")
        }
        return graph
    }

    static func missingProducts(_ container: Container, _ graph: PackageGraphPIF) -> [String] {
        var out: [String] = []
        for p in container.projects {
            for t in p.targets {
                for id in t.references("packageProductDependencies") {
                    guard let name = p.proj[id]?.string("productName"), !name.hasPrefix("plugin:"),
                          graph.product(name, identity: nil) == nil, !out.contains(name) else { continue }
                    out.append(name)
                }
            }
        }
        return out
    }

    static func run(_ tool: String, _ args: [String]) -> (Int32, Data, String) {
        MainThreadGuard.blockingCall("swift package dump-pif")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        guard (try? p.run()) != nil else { return (-1, Data(), "cannot run \(tool)") }
        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let group = DispatchGroup()
        group.enter()
        let errHandle = err.fileHandleForReading
        Thread { box.data = errHandle.readDataToEndOfFile(); group.leave() }.start()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        return (p.terminationStatus, data, String(decoding: box.data, as: UTF8.self))
    }
}
