import Foundation

public enum SwiftToolchain {
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                              realPath: (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                              targetInfo: (String) -> Data? = { SwiftToolchain.targetInfo(swift: $0) }) -> String? {
        if let root = environment["SWIFTCODE_SWIFT_TOOLCHAIN"], !root.isEmpty, isExecutable(join(root, "usr/bin/swift")) {
            return root
        }
        var candidates: [String] = []
        if let exec = environment["SWIFT_EXEC"], !exec.isEmpty { candidates.append(exec) }
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(join(String(dir), "swift"))
        }
        candidates = candidates.filter(isExecutable)
        for c in candidates {
            if let root = root(ofExecutable: realPath(c)) { return root }
        }
        guard let first = candidates.first,
              let data = targetInfo(first),
              let root = root(fromTargetInfo: data),
              isExecutable(join(root, "usr/bin/swift")) else { return nil }
        return root
    }

    public static func root(ofExecutable path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        for suffix in ["/usr/local/bin", "/usr/bin"] where dir.hasSuffix(suffix) {
            let root = String(dir.dropLast(suffix.count))
            return root.isEmpty ? "/" : root
        }
        return nil
    }

    public static func root(fromTargetInfo data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = obj["paths"] as? [String: Any],
              let resource = paths["runtimeResourcePath"] as? String else { return nil }
        let trimmed = resource.hasSuffix("/") ? String(resource.dropLast()) : resource
        guard trimmed.hasSuffix("/usr/lib/swift") else { return nil }
        let root = String(trimmed.dropLast("/usr/lib/swift".count))
        return root.isEmpty ? "/" : root
    }

    public static func targetInfo(swift: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: swift)
        p.arguments = ["-print-target-info"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    static func join(_ dir: String, _ rest: String) -> String {
        dir.hasSuffix("/") ? dir + rest : dir + "/" + rest
    }
}
