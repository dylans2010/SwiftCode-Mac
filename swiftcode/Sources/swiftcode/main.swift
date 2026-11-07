import Foundation
import SwiftCodeProject
import SwiftCodeRelease
import SwiftCodeWorkspace
import SwiftCodeSettings
import SwiftCodePlist
import SwiftCodeMachO
import SwiftCodeBuild
import SwiftCodeProfiler
import SwiftCodePreviews
import SwiftCodeBuildServer
import SwiftCodeXcodebuild
import SwiftCodeAssetCatalog
import SwiftCodeStrings
import SwiftCodeMCP
import SwiftCodeIDEShell
import SwiftCodeIDECore
import SwiftCodeCompletion
import SwiftCodeSimLink

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: swiftcode describe <path.xcodeproj>
           swiftcode schemes <path.xcodeproj|.xcworkspace>
           swiftcode settings <path.xcodeproj> [-target T] [-configuration C] [-defaults file.json]
                          [--assigned-only] [--json] [NAME=value]...
           swiftcode macho <file>
           swiftcode deps <executable> --root <RuntimeRoot> [--tree]
           swiftcode dsc <dyld_shared_cache> [--images N] [--image <install-path>]
           swiftcode build <path.xcodeproj|.xcworkspace|dir> [-scheme S] [-configuration C]
                       [-destination D] [-derivedDataPath P] [--clean|--test|--build-for-testing|--test-without-building] [--quiet]
                       [--engine xcodebuild|swift-build|swiftpm] [NAME=value]...
           swiftcode pif <path.xcodeproj>
           swiftcode results <bundle.xcresult> [--json]     the tests a result bundle records (swiftcodebuild's bundles)
           swiftcode roundtrip [--print] <path.xcodeproj|.xcscheme|contents.xcworkspacedata>...
           swiftcode profile record|summary|tree|flame|annotate|symbolicate ...   (swiftcode profile for details)
           swiftcode preview --list <file.swift>
           swiftcode preview --render <out.png> <file.swift> [--name N]
           swiftcode bsp [serve|config|targets|args|prepare] <path.xcodeproj|.xcworkspace> ...   (swiftcode bsp for details)
           swiftcode assets compile|info|icon ...   (swiftcode assets for details)
           swiftcode strings compile|generate-symbols|extract|convert|info ...   (swiftcode strings for details)
           swiftcode mcp [--workspace P] [--allow-writes] [--http [PORT]]   the MCP server for coding agents (swiftcode mcp --help)
           swiftcode complete --file F --line L --column C [--backend ollama|llama-server|openai] [--model M] ...   predictive completion (swiftcode complete --help)
           swiftcode compare <left> <right> [--ancestor <base> [--merge <output>]]   unified diff, or a three-way merge
           swiftcode sim remote pair|devices|boot|run|view ...   a simulator host over SwiftCode's own link (swiftcode sim remote for details)
           swiftcode sim headset check|view|desktop|state ...     a visionOS device in a headset and back (swiftcode sim headset for details)
           swiftcode sim runtimes check|script ...   simulator runtimes and host setup (swiftcode sim runtimes for details)
           swiftcode runtime list|available|download|import|xcodebuild ...   get a simulator runtime (swiftcode runtime for details)
           swiftcode new --template <id> --name N [--org O] [--option key=value]... [--git] <dir>   New Project (swiftcode new --list)
           swiftcode --version

    """.utf8))
    exit(2)
}

func describe(_ path: String) throws {
    let (file, name) = PBXProj.locate(path)
    let proj = try PBXProj(contentsOf: file)
    print("\(name) (objectVersion \(proj.objectVersion), \(proj.objects.count) objects)")
    for target in proj.targets {
        let type = target.string("productType") ?? target.isa
        print("  target \(target.string("name") ?? "?")  [\(type)]")
        for config in proj.buildConfigurations(listID: target.string("buildConfigurationList")) {
            let settings = config["buildSettings"]?.dictionary?.count ?? 0
            print("    config \(config.string("name") ?? "?")  (\(settings) settings)")
        }
    }
}

func roundtrip(_ paths: [String], printOutput: Bool) -> Int32 {
    var failures: Int32 = 0
    for path in paths {
        let (file, name) = PBXProj.locate(path)
        do {
            let isXML = ["xcscheme", "xcworkspacedata"].contains(URL(fileURLWithPath: path).pathExtension)
            let source = isXML ? URL(fileURLWithPath: path) : file
            let original = try String(contentsOf: source, encoding: .utf8)
            let written = isXML
                ? XcodeXML.write(try XcodeXML.parse(original))
                : try PBXProj(parsing: original).serialized(projectName: name)
            if printOutput { print(written, terminator: "") }
            if written == original {
                FileHandle.standardError.write(Data("ok    \(path)\n".utf8))
            } else {
                failures = 1
                let a = original.split(separator: "\n", omittingEmptySubsequences: false)
                let b = written.split(separator: "\n", omittingEmptySubsequences: false)
                let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                let want = i < a.count ? String(a[i]) : "<eof>"
                let got = i < b.count ? String(b[i]) : "<eof>"
                FileHandle.standardError.write(Data("DIFF  \(path)\n  line \(i + 1)\n  want: \(want)\n  got:  \(got)\n".utf8))
            }
        } catch {
            failures = 1
            FileHandle.standardError.write(Data("ERROR \(path): \(error)\n".utf8))
        }
    }
    return failures
}

func schemes(_ path: String) throws {
    let url = URL(fileURLWithPath: path)
    var containers = [url]
    if url.pathExtension == "xcworkspace" {
        containers += try Workspace(contentsOf: path).projectPaths.map { URL(fileURLWithPath: $0) }
    }
    for c in containers where c.pathExtension == "xcodeproj" {
        guard let proj = try? PBXProj(contentsOf: c.appendingPathComponent("project.pbxproj")) else { continue }
        let dir = proj.projectDirectory(xcodeprojURL: c)
        let parents = proj.parentMap()
        for ref in proj.project?["projectReferences"]?.array ?? [] {
            guard let id = ref.dictionary?["ProjectRef"]?.string,
                  let path = proj.resolvedPath(of: id, projectDirectory: dir, parents: parents), path.hasPrefix("/") else { continue }
            containers.append(URL(fileURLWithPath: path))
        }
    }
    var seen = Set<String>()
    for c in containers {
        for s in Scheme.discover(in: c) where seen.insert(s.name).inserted {
            let targets = s.buildEntries.map(\.reference.blueprintName).joined(separator: ", ")
            print("\(s.name)\t\(s.isShared ? "shared" : "user")\t[\(targets)]\tlaunch=\(s.launchTarget?.blueprintName ?? "-")\ttest=\(s.configuration(for: "TestAction"))")
        }
    }
}

func settings(_ rest: [String]) throws {
    var path: String?
    var target: String?
    var configuration: String?
    var defaultsFile: String?
    var assignedOnly = false
    var json = false
    var overrides: [String: String] = [:]
    var it = rest.makeIterator()
    while let a = it.next() {
        switch a {
        case "-target": target = it.next()
        case "-configuration": configuration = it.next()
        case "-defaults": defaultsFile = it.next()
        case "--assigned-only": assignedOnly = true
        case "--json": json = true
        default:
            if let eq = a.firstIndex(of: "="), !a.hasPrefix("-") {
                overrides[String(a[..<eq])] = String(a[a.index(after: eq)...])
            } else { path = a }
        }
    }
    guard let path else { usage() }
    let (file, _) = PBXProj.locate(path)
    let xcodeproj = file.deletingLastPathComponent()
    let proj = try PBXProj(contentsOf: file)
    var builder = ProjectSettingsBuilder(proj: proj, xcodeprojURL: xcodeproj)
    builder.overrides = overrides
    builder.developerDirectory = Workspace.activeDeveloperDirectory()
    if let dev = builder.developerDirectory {
        let catalog = SDKCatalog(developerDirectory: dev)
        builder.sdkLookup = { catalog.lookup($0) }
    }
    if let defaultsFile {
        let data = try Data(contentsOf: URL(fileURLWithPath: defaultsFile))
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
        builder.defaults = SettingsLevel(name: "defaults", literals: dict)
    }
    let config = configuration
        ?? proj.objects[proj.project?.string("buildConfigurationList") ?? ""]?.string("defaultConfigurationName")
        ?? "Release"
    let resolved = try builder.resolve(target: target ?? proj.targets.first?.string("name"), configuration: config)
    var names = resolved.settings.names
    if assignedOnly {
        let defined = Set(resolved.definedLevelNames)
        names = names.filter { resolved.settings.isAssigned($0, inLevels: defined) }
    }
    if json {
        let dict = Dictionary(uniqueKeysWithValues: names.map { ($0, resolved.settings[$0]) })
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        for n in names { print("    \(n) = \(resolved.settings[n])") }
    }
    for d in resolved.diagnostics { FileHandle.standardError.write(Data("warning: \(d)\n".utf8)) }
}

func describeMachO(_ image: MachOImage, indent: String = "") {
    let type = image.fileType.map { "\($0)" } ?? hex(image.fileTypeRaw)
    print("\(indent)\(image.isArm64 ? "arm64" : hex(image.cpuType)) \(type)\(image.isEncrypted ? "  [ENCRYPTED]" : "")")
    if let b = image.buildVersion {
        print("\(indent)platform \(b.platform.map { "\($0)" } ?? "\(b.platformRaw)")  minos \(b.minOS)  sdk \(b.sdk)")
    }
    if let u = image.uuid { print("\(indent)uuid \(u.uuidString)") }
    if let n = image.installName { print("\(indent)install name \(n)") }
    if let d = image.dylinker { print("\(indent)dylinker \(d)") }
    if let e = image.entryOffset { print("\(indent)entry __TEXT+\(hex(e))") }
    for seg in image.segments {
        print("\(indent)segment \(seg.name.padding(toLength: 16, withPad: " ", startingAt: 0)) vm \(hex(seg.vmAddress)) +\(hex(seg.vmSize))  \(seg.initialProtection)/\(seg.maxProtection)  \(seg.sections.count) sections")
    }
    for d in image.dylibs { print("\(indent)links \(d.path)\(d.kind == .normal ? "" : " (\(d.kind.rawValue))")") }
    for r in image.rpaths { print("\(indent)rpath \(r)") }
    print("\(indent)code signature: \(image.codeSignature != nil ? "yes" : "no")  chained fixups: \(image.chainedFixups != nil ? "yes" : "no")")
}

func machoCommand(_ path: String) throws {
    let file = try MachOFile(contentsOf: URL(fileURLWithPath: path))
    if file.slices.count > 1 { print("universal: \(file.slices.map(\.name).joined(separator: ", "))") }
    for slice in file.slices {
        if file.slices.count > 1 { print("slice \(slice.name)") }
        describeMachO(try MachOImage(file.reader, at: slice.offset))
    }
}

func dscCommand(_ rest: [String]) throws {
    guard let path = rest.first(where: { !$0.hasPrefix("--") && !(Int($0) != nil) }) else { usage() }
    let limit = rest.firstIndex(of: "--images").flatMap { rest.indices.contains($0 + 1) ? Int(rest[$0 + 1]) : nil } ?? 10
    let wanted = rest.firstIndex(of: "--image").flatMap { rest.indices.contains($0 + 1) ? rest[$0 + 1] : nil }
    let cache = try SharedCache(contentsOf: URL(fileURLWithPath: path))
    print("arch \(cache.architecture)  platform \(cache.platform.map { "\($0)" } ?? "\(cache.platformRaw)")  simulator \(cache.isSimulator)  format \(cache.formatVersion)  os \(cache.osVersion.map { "\($0)" } ?? "?")")
    print("shared region \(hex(cache.sharedRegionStart)) +\(hex(cache.sharedRegionSize))")
    for f in cache.files {
        print("file \(f.url.lastPathComponent)  uuid \(f.uuid.uuidString)")
        for m in f.mappings {
            print("    map \(hex(m.address)) +\(hex(m.size)) @file \(hex(m.fileOffset))  \(m.initialProtection)/\(m.maxProtection)  flags \(hex(m.flags))")
        }
    }
    print("\(cache.images.count) images")
    if let wanted {
        guard let img = cache.image(path: wanted) else { throw MachOError("no image \(wanted) in cache") }
        print("image \(img.path) at \(hex(img.address))")
        describeMachO(try cache.machO(for: img), indent: "    ")
        return
    }
    for img in cache.images.prefix(limit) { print("    \(hex(img.address))  \(img.path)") }
}

func depsCommand(_ rest: [String]) throws {
    guard let ri = rest.firstIndex(of: "--root"), rest.indices.contains(ri + 1),
          let exe = rest.first(where: { !$0.hasPrefix("--") && $0 != rest[ri + 1] }) else { usage() }
    let root = rest[ri + 1].hasSuffix("/") ? String(rest[ri + 1].dropLast()) : rest[ri + 1]
    let cachePath = root + "/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64"
    let cache = FileManager.default.fileExists(atPath: cachePath) ? try SharedCache(contentsOf: URL(fileURLWithPath: cachePath)) : nil
    var closure = DependencyClosure(root: root, cache: cache)
    try closure.resolve(executable: exe)
    let images = closure.order.dropFirst().compactMap { closure.nodes[$0] }
    let fromCache = images.filter { if case .sharedCache = $0.source { true } else { false } }.count
    print("\(images.count) images (\(fromCache) from the shared cache, \(images.count - fromCache) from files)")
    let fatal = closure.missing.filter(\.isFatal), weak = closure.missing.filter { !$0.isFatal }
    print("missing: \(fatal.count) required, \(weak.count) weak")
    for m in fatal { print("  REQUIRED \(m.path)  (needed by \(m.requiredBy))") }
    for m in weak.prefix(10) { print("  weak     \(m.path)  (needed by \(m.requiredBy))") }
    let platforms = Dictionary(grouping: images, by: { $0.image.buildVersion?.platform.map { "\($0)" } ?? "none" }).mapValues(\.count)
    print("platforms: \(platforms.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
    if rest.contains("--tree") {
        for key in closure.order { if let n = closure.nodes[key] { print("\(n.installPath)  [\(n.source)]  -> \(n.dependencies.count)") } }
    }
}

func resultsCommand(_ args: [String]) -> Int32 {
    let json = args.contains("--json")
    guard let path = args.first(where: { $0 != "--json" }) else { usage() }
    do {
        let reader = try XCResultReader(URL(fileURLWithPath: path))
        let tests = try reader.tests()
        if json {
            let list: [[String: Any]] = tests.map { t in
                var o: [String: Any] = ["run": t.run, "target": t.target, "identifier": t.identifier, "name": t.name,
                                        "status": t.status, "duration": t.duration]
                if !t.failures.isEmpty {
                    o["failures"] = t.failures.map { f in
                        ["message": f.message, "file": f.file ?? "", "line": f.line ?? 0] as [String: Any]
                    }
                }
                if let s = t.skipMessage { o["skipMessage"] = s }
                if !t.arguments.isEmpty { o["arguments"] = t.arguments }
                return o
            }
            let data = try JSONSerialization.data(withJSONObject: ["tests": list, "metrics": try reader.metrics()], options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        } else {
            for t in tests {
                let args = t.arguments.isEmpty ? "" : " [" + t.arguments.joined(separator: ", ") + "]"
                print("\(t.status.padding(toLength: 8, withPad: " ", startingAt: 0)) \(t.run) \(t.target)/\(t.identifier)\(args) (\(String(format: "%.3f", t.duration)) s)")
                for f in t.failures { print("    \(f.file.map { "\($0):\(f.line ?? 0): " } ?? "")\(f.message)") }
                if let s = t.skipMessage { print("    \(s)") }
            }
            let failed = tests.filter { $0.status == "Failure" }.count
            let skipped = tests.filter { $0.status == "Skipped" }.count
            print("\(tests.count) tests, \(failed) failed, \(skipped) skipped")
        }
        return tests.contains { $0.status == "Failure" } ? 1 : 0
    } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        return 2
    }
}

func buildCommand(_ args: [String]) -> Int32 {
    var request = BuildRequest(container: .package(FileManager.default.currentDirectoryPath))
    var quiet = false
    var engineName: String?
    var i = 0
    func value() -> String {
        i += 1
        guard i < args.count else { usage() }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "-scheme": request.scheme = value()
        case "-configuration": request.configuration = value()
        case "-destination": request.destination = value()
        case "-derivedDataPath": request.derivedDataPath = value()
        case "--clean": request.action = .clean
        case "--test": request.action = .test
        case "--build-for-testing": request.action = .buildForTesting
        case "--test-without-building": request.action = .testWithoutBuilding
        case "--quiet": quiet = true
        case "--engine": engineName = value()
        case let a where a.contains("=") && !a.hasPrefix("-"):
            let eq = a.firstIndex(of: "=")!
            request.settings.append((String(a[..<eq]), String(a[a.index(after: eq)...])))
        case let a where !a.hasPrefix("-"): request.container = .init(path: a)
        default: usage()
        }
        i += 1
    }
    let isLinux = CommandLineBuild.isLinuxHost
    guard let choice = CommandLineBuild.engine(named: engineName, container: request.container, isLinux: isLinux) else { usage() }
    let engine: BuildEngine
    do {
        engine = try CommandLineBuild.make(choice, isLinux: isLinux)
    } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        return 1
    }
    let op = engine.start(request)
    let isQuiet = quiet
    let result = op.runBlocking { event in
        switch event {
        case .output(let line) where !isQuiet: print(line)
        case .issue(let d) where isQuiet && d.severity != .note:
            print(d)
            d.notes.forEach { print("  \($0)") }
        default: break
        }
    }
    let verb = switch request.action {
    case .clean: "CLEAN"
    case .buildForTesting: "TEST BUILD"
    case .test: "TEST"
    case .testWithoutBuilding: "TEST EXECUTE"
    default: "BUILD"
    }
    FileHandle.standardError.write(Data("swiftcode: \(verb) \(result.status) (\(result.errorCount) errors, \(result.warningCount) warnings)\n".utf8))
    return result.status == .succeeded ? 0 : 1
}

func preview(_ args: [String]) -> Int32 {
    var it = args.makeIterator()
    var list = false, render: String?, file: String?, name: String?
    while let a = it.next() {
        switch a {
        case "--list": list = true
        case "--render": render = it.next()
        case "--name": name = it.next()
        default: file = a
        }
    }
    guard let file, list || render != nil, let text = try? String(contentsOfFile: file, encoding: .utf8) else { usage() }
    let previews = PreviewDiscovery.previews(in: text)
    if list {
        for p in previews {
            let kind: String = switch p.kind { case .macro: "#Preview"; case .provider(let t): "PreviewProvider \(t)" }
            print("\(p.line)\t\(p.name)\t\(kind)\(p.traits.isEmpty ? "" : "\ttraits: " + p.traits.joined(separator: ", "))")
        }
        return 0
    }
    guard let render else { usage() }
    let fm = FileManager.default
    let starts = [URL(fileURLWithPath: fm.currentDirectoryPath), URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
    let result = PreviewRenderRunner.render(file: file, name: name, output: render, starts: starts) {
        FileHandle.standardError.write(Data("swiftcode: \($0)\n".utf8))
    }
    switch result {
    case .success(let url):
        print(url.path)
        return 0
    case .failure(let f):
        if !f.log.isEmpty { FileHandle.standardError.write(Data(f.log.utf8)) }
        FileHandle.standardError.write(Data("swiftcode: \(f.description)\n".utf8))
        return f.status
    }
}

SwiftCodeRelease.handleVersionFlag(tool: "swiftcode")
SwiftCodeRelease.adoptBundledHelpers()
var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()
switch command {
case "describe":
    guard args.count == 1 else { usage() }
    do { try describe(args[0]) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "schemes":
    guard args.count == 1 else { usage() }
    do { try schemes(args[0]) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "settings":
    do { try settings(args) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "macho":
    guard args.count == 1 else { usage() }
    do { try machoCommand(args[0]) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "deps":
    do { try depsCommand(args) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "dsc":
    do { try dscCommand(args) } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "_strip-settings":
    guard args.count >= 2 else { usage() }
    do {
        let (file, _) = PBXProj.locate(args[0])
        var proj = try PBXProj(contentsOf: file)
        let keep = args.dropFirst(2).compactMap { a -> (String, String)? in
            a.firstIndex(of: "=").map { (String(a[..<$0]), String(a[a.index(after: $0)...])) }
        }
        let projectConfigs = Set(proj.buildConfigurations(listID: proj.project?.string("buildConfigurationList")).map(\.id))
        for (id, var obj) in proj.objects where obj.isa == "XCBuildConfiguration" {
            var bs = PlistDictionary()
            if projectConfigs.contains(id) { for (k, v) in keep { bs[k] = .string(v) } }
            obj["buildSettings"] = .dictionary(bs)
            for k in ["baseConfigurationReference", "baseConfigurationReferenceAnchor", "baseConfigurationReferenceRelativePath"] { obj[k] = nil }
            proj[id] = obj
        }
        let packageClasses: Set<String> = ["XCLocalSwiftPackageReference", "XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency"]
        let doomed = Set(proj.objects.values.filter { packageClasses.contains($0.isa) || ($0.isa == "PBXBuildFile" && $0["productRef"] != nil) }.map(\.id))
        for id in doomed { proj[id] = nil }
        for (id, var obj) in proj.objects {
            var changed = false
            for key in ["files", "packageReferences", "packageProductDependencies"] {
                if let refs = obj[key]?.array {
                    let kept = refs.filter { !doomed.contains($0.string ?? "") }
                    if kept.count != refs.count { obj[key] = .array(kept); changed = true }
                }
            }
            if changed { proj[id] = obj }
        }
        let out = URL(fileURLWithPath: args[1])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try proj.serialized(projectName: out.deletingPathExtension().lastPathComponent)
            .write(to: out.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
    } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "build":
    exit(buildCommand(args))
case "results":
    exit(resultsCommand(args))
case "pif":
    guard args.count == 1 else { usage() }
    do {
        let url = URL(fileURLWithPath: args[0])
        let pif = try PIFGenerator(proj: try PBXProj(contentsOf: url), xcodeprojURL: url).pif()
        FileHandle.standardOutput.write(try pif.serialized())
        print()
    } catch {
        FileHandle.standardError.write(Data("swiftcode: \(error)\n".utf8))
        exit(1)
    }
case "profile":
    exit(GaugeCLI.run(args))
case "preview":
    exit(preview(args))
case "bsp":
    exit(BuildServerMain.run(args))
case "assets":
    exit(AssetsCLI.run(args))
case "strings":
    exit(StringsCLI.run(args))
case "complete":
    exit(CompleteCLI.runBlocking(args))
case "mcp":
    MCPCommand.run(args)
case "compare":
    exit(FileCompare.run(args))
case "sim":
    if args.first == "headset" { exit(runHeadset(Array(args.dropFirst()))) }
    if args.first == "runtimes" { exit(runRuntimes(Array(args.dropFirst()))) }
    guard args.first == "remote" else { usage() }
    if let switched = HeadsetCLI.remoteView(Array(args.dropFirst())) { exit(runHeadset(switched.headset, then: switched.viewer)) }
    exit(SimRemoteCLI.main(Array(args.dropFirst())))
case "runtime":
    exit(runRuntimeDownloads(args))
case "new":
    exit(NewProjectCLI.run(args))
case "roundtrip":
    let printOutput = args.contains("--print")
    let paths = args.filter { $0 != "--print" }
    guard !paths.isEmpty else { usage() }
    exit(roundtrip(paths, printOutput: printOutput))
default:
    usage()
}

func runHeadset(_ args: [String], then viewer: [String]? = nil) -> Int32 {
    let box = HeadsetExit()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.status = await HeadsetCLI.main(args)
        done.signal()
    }
    done.wait()
    if box.status == 0, let viewer { return SimRemoteCLI.main(viewer) }
    return box.status
}

final class HeadsetExit: @unchecked Sendable { var status: Int32 = 1 }

func runRuntimes(_ args: [String]) -> Int32 {
    let box = HeadsetExit()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.status = await RuntimeCLI.main(args)
        done.signal()
    }
    done.wait()
    return box.status
}

func runRuntimeDownloads(_ args: [String]) -> Int32 {
    let box = HeadsetExit()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.status = await RuntimeDownloadCLI.main(args)
        done.signal()
    }
    done.wait()
    return box.status
}
