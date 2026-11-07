import Foundation

public enum NestedCode {
    static let codeFolders = [
        "Frameworks", "SharedFrameworks", "PlugIns", "Extensions", "XPCServices", "Library/LoginItems",
        "Library/SystemExtensions", "Library/QuickLook", "Library/Spotlight", "Helpers", "MacOS", "Watch", "AppClips",
    ]
    static let bundleExtensions: Set<String> = ["app", "appex", "framework", "xpc", "bundle", "systemextension", "qlgenerator", "mdimporter", "plugin"]

    public static func isMachO(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        let d = h.readData(ofLength: 4)
        guard d.count == 4 else { return false }
        let m = d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(m)
    }

    static func contentsFolder(_ bundle: URL) -> URL {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents")
        if fm.fileExists(atPath: contents.path) { return contents }
        let versions = bundle.appendingPathComponent("Versions")
        if let current = try? fm.destinationOfSymbolicLink(atPath: versions.appendingPathComponent("Current").path), !current.hasPrefix("/") {
            return versions.appendingPathComponent(current)
        }
        return bundle
    }

    static func mainExecutable(_ contents: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: contents.appendingPathComponent("Info.plist").path),
              let info = try? Entitlements.fromPropertyList(data) else { return nil }
        return info["CFBundleExecutable"]?.stringValue
    }

    public static func signingOrder(bundle: URL) -> [URL] {
        var out: [URL] = []
        visit(bundle.standardizedFileURL, into: &out)
        return out
    }

    static func visit(_ bundle: URL, into out: inout [URL]) {
        let fm = FileManager.default
        let contents = contentsFolder(bundle)
        let main = mainExecutable(contents) ?? bundle.deletingPathExtension().lastPathComponent
        for folder in codeFolders {
            let dir = contents.appendingPathComponent(folder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            for n in names {
                let item = dir.appendingPathComponent(n)
                let ext = item.pathExtension
                var itemIsDir: ObjCBool = false
                _ = fm.fileExists(atPath: item.path, isDirectory: &itemIsDir)
                if itemIsDir.boolValue {
                    if bundleExtensions.contains(ext) { visit(item, into: &out) }
                } else if folder == "MacOS" && n == main {
                    continue
                } else if ext == "dylib" || isMachO(item.path) {
                    out.append(item)
                }
            }
        }
        out.append(bundle)
    }
}

public enum CodesignCommand {
    public static let codesign = "/usr/bin/codesign"

    public static func codesign(item: String, identity: String, entitlements: String? = nil, preserve: Bool = false,
                                options: [String] = [], timestamp: Bool = false) -> [String] {
        var a = ["--force", "--sign", identity]
        if let entitlements { a += ["--entitlements", entitlements] }
        if preserve && entitlements == nil { a.append("--preserve-metadata=identifier,entitlements,flags") }
        if !options.isEmpty { a += ["--options", options.joined(separator: ",")] }
        a.append(timestamp && identity != "-" ? "--timestamp" : "--timestamp=none")
        a.append(item)
        return a
    }

    public static func rcodesignAdHoc(item: String, entitlements: String? = nil) -> [String] {
        var a = ["sign"]
        if let entitlements { a += ["--entitlements-xml-file", entitlements] }
        a.append(item)
        return a
    }

    public static func resign(bundle: URL, identity: String, runner: CommandRunner = .system) -> String? {
        for item in NestedCode.signingOrder(bundle: bundle) {
            let r = runner.run(codesign, codesign(item: item.path, identity: identity, preserve: true))
            if r.status != 0 { return "codesign failed for \(item.path) (exit \(r.status))" }
        }
        return nil
    }
}
