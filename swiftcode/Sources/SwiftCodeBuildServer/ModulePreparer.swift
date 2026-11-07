import Foundation
import SwiftCodeSubprocess
import SwiftCodeXcodebuild

public final class ModulePreparer: @unchecked Sendable {
    public let model: IndexModel
    public let swiftc: String?
    public let packageHelper: String?
    private let lock = NSLock()
    private let log: @Sendable (String) -> Void

    public init(model: IndexModel, swiftc: String? = ModulePreparer.locateSwiftc(),
                packageHelper: String? = SwiftBuildSettingsProvider.locate(environment: ProcessInfo.processInfo.environment,
                                                                            executableDirectory: Bundle.main.executableURL?.deletingLastPathComponent().path),
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.model = model
        self.swiftc = swiftc
        self.packageHelper = packageHelper
        self.log = log
    }

    public struct Step: Equatable, Sendable {
        public var target: String
        public var ran: Bool
        public var succeeded: Bool
        public var output: String
        public var packages = false
    }

    @discardableResult
    public func prepare(_ targetIDs: [String]) -> [Step] {
        lock.lock()
        defer { lock.unlock() }
        let graph = model.graph
        var steps: [Step] = []
        var done: Set<String> = []
        var packagesBuilt: Set<String> = []
        for id in targetIDs {
            guard let t = graph.target(id: id) else { continue }
            let deps = graph.transitiveDependencies(of: t)
            if let packages = model.packages {
                let users = (deps + [t]).filter { packages.products[$0.id] != nil }
                let guids = users.flatMap { packages.products[$0.id] ?? [] }.filter { !packagesBuilt.contains($0) }
                if let first = users.first, !guids.isEmpty, let ctx = model.compileContext(first.id),
                   let step = buildPackageProducts(guids.uniqued(), packages: packages, client: ctx) {
                    steps.append(step)
                    if step.succeeded { packagesBuilt.formUnion(guids) }
                }
            }
            for d in deps + [t] where done.insert(d.id).inserted {
                guard let ctx = model.compileContext(d.id) else { continue }
                layOut(ctx)
                let isSelf = d.id == t.id
                if d.hasSwift && (!isSelf || d.hasClangSources) {
                    let step = emitModule(ctx)
                    steps.append(step)
                    if step.ran && step.succeeded { layOut(ctx) }
                }
            }
        }
        return steps
    }

    func buildPackageProducts(_ guids: [String], packages: PackageProducts, client ctx: TargetCompileContext) -> Step? {
        guard let helper = packageHelper else {
            log("Package products are not built: the swiftcode-swb helper was not found (SWIFTCODE_SWB)")
            return nil
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("swiftcode-bsp-packages-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        let context = model.context
        let arena = Arena.forContainer(packages.pif.container, derivedDataPath: context.indexRoot, derivedDataRoot: "")
        let sdk = ctx.value("PLATFORM_NAME")
        var destination: RunDestination?
        if !context.isLinuxHost, !sdk.isEmpty {
            destination = sdk == "macosx" ? .hostMac(architecture: ctx.architecture)
                : RunDestination(platform: sdk, sdk: sdk, sdkVariant: nil, targetArchitecture: ctx.architecture, supportedArchitectures: [ctx.architecture])
        }
        let configuration = ctx.value("CONFIGURATION").isEmpty ? "Debug" : ctx.value("CONFIGURATION")
        let parameters = BuildParameters(action: "build", configuration: configuration, arena: arena, runDestination: destination,
                                         overrides: [("CODE_SIGNING_ALLOWED", "NO")])
        let pifURL = work.appendingPathComponent("workspace.pif.json"), requestURL = work.appendingPathComponent("build.json")
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try packages.pif.serialized().write(to: pifURL)
            let request: [String: Any] = [
                "command": "build", "locationStyle": "regular", "pif": pifURL.path, "parameters": parameters.json, "targets": guids,
                "containerPath": packages.pif.container.url.path, "parallel": true, "implicitDependencies": true,
                "hideShellScriptEnvironment": true, "continueAfterErrors": true,
            ]
            try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]).write(to: requestURL)
        } catch {
            return Step(target: ctx.target.id, ran: false, succeeded: false, output: "cannot write the package build request: \(error)", packages: true)
        }
        log("Building the package products of \(ctx.target.name)")
        let result = try? Subprocess.run(helper, ["build", requestURL.path], currentDirectory: URL(fileURLWithPath: ctx.projectDirectory))
        let ok = result?.status == 0
        let errors = (result?.stdoutText ?? "").split(separator: "\n").compactMap { line -> String? in
            guard line.contains("\"error\""), let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            return Self.diagnosticMessage(o)
        }
        let output = (errors + [result?.stderrText ?? ""]).filter { !$0.isEmpty }.joined(separator: "\n")
        if !ok { log("Building the package products of \(ctx.target.name) failed:\n\(output)") }
        return Step(target: ctx.target.id, ran: true, succeeded: ok, output: output, packages: true)
    }

    static func diagnosticMessage(_ o: [String: Any]) -> String? {
        for v in o.values {
            if let d = v as? [String: Any] {
                if d["kind"] as? String == "error", let m = d["message"] as? String { return m }
                if let m = diagnosticMessage(d) { return m }
            }
        }
        return nil
    }

    func layOut(_ ctx: TargetCompileContext) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: ctx.productsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: (ctx.objectFile(for: "x.o") as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let exported = ctx.target.headers.filter { $0.visibility != .project }
        guard !exported.isEmpty || (ctx.target.hasSwift && ctx.target.hasClangSources) else { return }
        try? fm.createDirectory(atPath: ctx.includeDirectory, withIntermediateDirectories: true)
        var names: Set<String> = []
        for h in exported {
            let name = (h.path as NSString).lastPathComponent
            names.insert(name)
            let link = ctx.includeDirectory + "/" + name
            if (try? fm.destinationOfSymbolicLink(atPath: link)) == h.path { continue }
            try? fm.removeItem(atPath: link)
            try? fm.createSymbolicLink(atPath: link, withDestinationPath: h.path)
        }
        let generated = (ctx.objcHeaderPath as NSString).lastPathComponent
        for name in (try? fm.contentsOfDirectory(atPath: ctx.includeDirectory)) ?? [] where !names.contains(name) {
            let p = ctx.includeDirectory + "/" + name
            if (try? fm.destinationOfSymbolicLink(atPath: p)) != nil { try? fm.removeItem(atPath: p) }
        }
        if ctx.exportsClangModule {
            let text = Self.moduleMap(module: ctx.moduleName, publicHeaders: ctx.target.headers.filter { $0.visibility == .public }.map {
                ($0.path as NSString).lastPathComponent
            }, excluding: fm.fileExists(atPath: ctx.objcHeaderPath) ? [generated] : [])
            if (try? String(contentsOfFile: ctx.moduleMapPath, encoding: .utf8)) != text {
                try? text.write(toFile: ctx.moduleMapPath, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func moduleMap(module: String, publicHeaders: [String], excluding: [String] = []) -> String {
        var lines = ["module \(module) {"]
        if publicHeaders.contains(module + ".h") {
            lines.append("  umbrella header \"\(module).h\"")
            for e in excluding { lines.append("  exclude header \"\(e)\"") }
            lines.append("  export *")
            lines.append("  module * { export * }")
        } else {
            for h in publicHeaders.sorted() { lines.append("  header \"\(h)\"") }
            lines.append("  export *")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func emitModuleArguments(_ ctx: TargetCompileContext) -> [String] {
        var a = CompilerArguments.swiftModuleArguments(ctx)
        a += ["-emit-module", "-emit-module-path", ctx.swiftModulePath, "-experimental-skip-non-inlinable-function-bodies"]
        if ctx.isDarwinTarget { a += ["-emit-objc-header", "-emit-objc-header-path", ctx.objcHeaderPath] }
        return a
    }

    func emitModule(_ ctx: TargetCompileContext) -> Step {
        let args = Self.emitModuleArguments(ctx)
        let stamp = ctx.swiftModulePath + ".swiftcode-args"
        let fm = FileManager.default
        if isUpToDate(ctx, args: args, stamp: stamp) {
            return Step(target: ctx.target.id, ran: false, succeeded: true, output: "")
        }
        guard let swiftc else { return Step(target: ctx.target.id, ran: false, succeeded: false, output: "no Swift compiler found") }
        if ctx.isDarwinTarget { try? fm.createDirectory(atPath: ctx.includeDirectory, withIntermediateDirectories: true) }
        log("Emitting module \(ctx.moduleName)")
        let result = try? Subprocess.run(swiftc, args, currentDirectory: URL(fileURLWithPath: ctx.projectDirectory))
        let ok = result?.status == 0
        let output = (result?.stderrText ?? "") + (result?.stdoutText ?? "")
        if ok { try? args.joined(separator: "\n").write(toFile: stamp, atomically: true, encoding: .utf8) } else { try? fm.removeItem(atPath: stamp) }
        if !ok { log("Emitting module \(ctx.moduleName) failed:\n\(output)") }
        return Step(target: ctx.target.id, ran: true, succeeded: ok, output: output)
    }

    func isUpToDate(_ ctx: TargetCompileContext, args: [String], stamp: String) -> Bool {
        guard (try? String(contentsOfFile: stamp, encoding: .utf8)) == args.joined(separator: "\n"),
              let built = Self.modified(ctx.swiftModulePath) else { return false }
        var inputs = ctx.target.sources.map(\.path) + ctx.target.headers.map(\.path)
        let bridging = ctx.value("SWIFT_OBJC_BRIDGING_HEADER")
        if !bridging.isEmpty { inputs.append(ctx.absolute(bridging)) }
        for d in model.graph.transitiveDependencies(of: ctx.target) {
            if let dc = model.compileContext(d.id) { inputs.append(dc.swiftModulePath) }
        }
        return inputs.allSatisfy { (Self.modified($0) ?? .distantPast) <= built }
    }

    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    public static func locateSwiftc(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let p = environment["SWIFTCODE_SWIFTC"], FileManager.default.isExecutableFile(atPath: p) { return p }
        #if os(macOS)
        if let out = try? Subprocess.run("/usr/bin/xcrun", ["--find", "swiftc"]), out.status == 0 {
            let p = out.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { return p }
        }
        #endif
        for dir in (environment["PATH"] ?? "/usr/bin").split(separator: ":") {
            let c = "\(dir)/swiftc"
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        return nil
    }
}
