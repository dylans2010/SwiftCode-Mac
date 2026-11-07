import Foundation

public struct SDKEntry: Equatable, Sendable {
    public var bundleName: String
    public var path: String
    public var canonicalName: String
    public var displayName: String
    public var version: String
    public var isBaseSDK: Bool
    public var platformName: String
    public var platformDescription: String
    public var platformVersion: String
    public var platformPath: String
    public var systemVersion: [String: String]

    public var infoLines: [(key: String, value: String)] {
        var lines = [("SDKVersion", version), ("Path", path), ("PlatformVersion", platformVersion), ("PlatformPath", platformPath)]
        for k in systemVersion.keys.sorted() { lines.append((k, systemVersion[k]!)) }
        return lines
    }

    public var json: [String: Any] {
        var d: [String: Any] = [
            "canonicalName": canonicalName, "displayName": displayName, "isBaseSdk": isBaseSDK,
            "platform": platformName, "platformPath": platformPath, "platformVersion": platformVersion,
            "sdkPath": path, "sdkVersion": version,
        ]
        for (k, v) in systemVersion {
            d[k.prefix(1).lowercased() + k.dropFirst()] = v
        }
        return d
    }
}

public struct SDKRegistry: Sendable {
    public var developerDirectory: String
    public var entries: [SDKEntry]

    public init(developerDirectory: String) {
        self.developerDirectory = developerDirectory
        let fm = FileManager.default
        let platformsDir = developerDirectory + "/Platforms"
        var all: [SDKEntry] = []
        for p in ((try? fm.contentsOfDirectory(atPath: platformsDir)) ?? []).sorted() where p.hasSuffix(".platform") {
            let platformPath = platformsDir + "/" + p
            let info = Self.plist(platformPath + "/Info.plist")
            let platformName = info["Name"] as? String ?? String(p.dropLast(".platform".count)).lowercased()
            let description = info["Description"] as? String ?? platformName
            let platformVersion = info["Version"] as? String ?? info["CFBundleShortVersionString"] as? String ?? ""
            let sdksDir = platformPath + "/Developer/SDKs"
            let names = ((try? fm.contentsOfDirectory(atPath: sdksDir)) ?? []).filter { $0.hasSuffix(".sdk") }.sorted()
            func real(_ n: String) -> String { URL(fileURLWithPath: sdksDir + "/" + n).resolvingSymlinksInPath().path }
            let versioned = Set(names.filter { $0.contains(where: \.isNumber) }.map(real))
            for n in names {
                if !n.contains(where: \.isNumber), versioned.contains(real(n)) { continue }
                let sdkPath = sdksDir + "/" + n
                guard let data = fm.contents(atPath: sdkPath + "/SDKSettings.json"),
                      let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let canonical = settings["CanonicalName"] as? String else { continue }
                let sv = Self.plist(sdkPath + "/System/Library/CoreServices/SystemVersion.plist").compactMapValues { $0 as? String }
                all.append(SDKEntry(
                    bundleName: n, path: sdkPath, canonicalName: canonical,
                    displayName: settings["DisplayName"] as? String ?? canonical,
                    version: settings["Version"] as? String ?? "",
                    isBaseSDK: (settings["IsBaseSDK"] as? String).map { $0.uppercased() == "YES" } ?? (settings["IsBaseSDK"] as? Bool ?? false),
                    platformName: platformName, platformDescription: description,
                    platformVersion: platformVersion, platformPath: platformPath, systemVersion: sv))
            }
        }
        entries = all.enumerated().sorted { a, b in
            let c = a.element.platformDescription.caseInsensitiveCompare(b.element.platformDescription)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)
    }

    static func plist(_ path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return obj
    }

    public func lookup(_ value: String, relativeTo cwd: String) -> SDKEntry? {
        if let e = entries.first(where: { $0.canonicalName == value }) { return e }
        let base = entries.filter { $0.canonicalName.hasPrefix(value) && $0.canonicalName.dropFirst(value.count).first?.isNumber == true }
        if let newest = base.max(by: { $0.version.compare($1.version, options: .numeric) == .orderedAscending }) {
            return base.first { $0.version == newest.version }
        }
        if value.contains("/") {
            let abs = value.hasPrefix("/") ? value : cwd + "/" + value
            let real = URL(fileURLWithPath: abs).resolvingSymlinksInPath().path
            return entries.first { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == real }
        }
        return nil
    }

    public func showsdksText() -> String {
        var out: [String] = []
        var current: String?
        for e in entries {
            if e.platformDescription != current {
                if current != nil { out.append("") }
                current = e.platformDescription
                out.append("\(e.platformDescription) SDKs:")
            }
            out.append("\t" + e.displayName.padding(toLength: max(30, e.displayName.count), withPad: " ", startingAt: 0) + "\t-sdk " + e.canonicalName)
        }
        out.append("")
        return out.joined(separator: "\n")
    }

    public static func versionBlock(_ e: SDKEntry) -> String {
        (["\(e.bundleName) - \(e.displayName) (\(e.canonicalName))"] + e.infoLines.map { "\($0.key): \($0.value)" }).joined(separator: "\n")
    }
}
