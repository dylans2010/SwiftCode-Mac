import Foundation

public struct PreviewIOSToolchain: Equatable, Sendable {
    public var developer: URL
    public var sdk: URL
    public var resourceDirectory: URL
    public var clangRuntime: URL
    public var linker: URL
    public var sdkVersion: String

    public init(developer: URL, sdk: URL, resourceDirectory: URL, clangRuntime: URL, linker: URL, sdkVersion: String) {
        self.developer = developer
        self.sdk = sdk
        self.resourceDirectory = resourceDirectory
        self.clangRuntime = clangRuntime
        self.linker = linker
        self.sdkVersion = sdkVersion
    }

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> Result<PreviewIOSToolchain, PreviewFailure> {
        let fm = FileManager.default
        guard let dev = environment["SWIFTCODE_USER_SDK"], !dev.isEmpty else {
            return .failure(.unsupported("UIKit previews compile with your own copy of the iOS Simulator SDK: set SWIFTCODE_USER_SDK to its developer folder "
                + "(the one Run on a simulator host uses; see scripts/swiftcode-ios-build-linux)."))
        }
        let developer = URL(fileURLWithPath: dev)
        let sdks = developer.appendingPathComponent("Platforms/iPhoneSimulator.platform/Developer/SDKs")
        let names = ((try? fm.contentsOfDirectory(atPath: sdks.path)) ?? []).filter { $0.hasPrefix("iPhoneSimulator") && $0.hasSuffix(".sdk") }
        guard let name = names.filter({ $0 != "iPhoneSimulator.sdk" }).sorted().last ?? names.first else {
            return .failure(.unsupported("No iPhoneSimulator SDK in \(sdks.path)."))
        }
        let sdk = sdks.appendingPathComponent(name)
        let tc = developer.appendingPathComponent("Toolchains/XcodeDefault.xctoolchain/usr/lib")
        let resources = tc.appendingPathComponent("swift")
        let clang = tc.appendingPathComponent("clang")
        let runtime = ((try? fm.contentsOfDirectory(atPath: clang.path)) ?? []).sorted().reversed()
            .map { clang.appendingPathComponent("\($0)/lib/darwin/libclang_rt.iossim.a") }
            .first { fm.fileExists(atPath: $0.path) }
        guard fm.fileExists(atPath: resources.path), let runtime else {
            return .failure(.unsupported("The SDK copy in \(dev) has no XcodeDefault toolchain resources (usr/lib/swift, libclang_rt.iossim.a)."))
        }
        var ld = environment["SWIFTCODE_LD64"].map { URL(fileURLWithPath: $0) }
        if ld == nil {
            let llvm = ((try? fm.contentsOfDirectory(atPath: "/usr/lib")) ?? []).filter { $0.hasPrefix("llvm-") }
                .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            ld = llvm.reversed().map { URL(fileURLWithPath: "/usr/lib/\($0)/bin/ld64.lld") }.first { fm.isExecutableFile(atPath: $0.path) }
        }
        guard let linker = ld, fm.isExecutableFile(atPath: linker.path) else {
            return .failure(.unsupported("UIKit previews link with an upstream ld64.lld: install LLVM's lld or set SWIFTCODE_LD64."))
        }
        return .success(PreviewIOSToolchain(developer: developer, sdk: sdk, resourceDirectory: resources, clangRuntime: runtime, linker: linker,
                                            sdkVersion: sdkVersion(sdk: sdk)))
    }

    public static func sdkVersion(sdk: URL) -> String {
        if let d = FileManager.default.contents(atPath: sdk.appendingPathComponent("SDKSettings.json").path),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let v = o["Version"] as? String, !v.isEmpty {
            return v
        }
        let digits = sdk.deletingPathExtension().lastPathComponent.drop { !$0.isNumber }
        return digits.isEmpty ? "17.0" : String(digits)
    }

    public func arguments(sources: [URL], output: URL, moduleName: String, library: Bool, moduleCache: URL, extra: [String] = []) -> [String] {
        var a = ["-target", PreviewPlatform.iOS.targetTriple(deploymentTarget: sdkVersion), "-sdk", sdk.path,
                 "-resource-dir", resourceDirectory.path, "-module-cache-path", moduleCache.standardizedFileURL.path,
                 "-module-name", moduleName, "-Onone", "-gnone", "-swift-version", "5",
                 "-use-ld=lld", "-ld-path=" + linker.path, "-Xlinker", clangRuntime.path]
        if library {
            a += ["-emit-library", "-parse-as-library", "-wmo", "-D", "DEBUG", "-D", "SWIFTCODE_PREVIEW",
                  "-Xlinker", "-install_name", "-Xlinker", "@rpath/\(output.lastPathComponent)"]
        }
        return a + extra + ["-o", output.path] + sources.map(\.path)
    }
}

extension PreviewHost {
    public static var bundledPlanSource: String {
        uikitSource
            .replacingOccurrences(of: #"?? "/tmp/swiftcode-previews""#, with: #"?? (Bundle.main.bundlePath + "/Previews")"#)
            .replacingOccurrences(of: "guard let h = dlopen(payload, RTLD_NOW | RTLD_LOCAL) else {",
                                  with: #"guard let h = dlopen(payload.hasPrefix("/") ? payload : previewDirectory + "/" + payload, RTLD_NOW | RTLD_LOCAL) else {"#)
    }
}
