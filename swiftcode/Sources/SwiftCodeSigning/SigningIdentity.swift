import Foundation

public struct SigningIdentity: Equatable, Sendable {
    public var hash: String
    public var name: String
    public var team: String?
    public var expires: Date?

    public init(hash: String, name: String, team: String? = nil, expires: Date? = nil) {
        self.hash = hash.uppercased()
        self.name = name
        self.team = team
        self.expires = expires
    }

    public var kind: String {
        name.firstIndex(of: ":").map { String(name[..<$0]) } ?? name
    }
}

public enum IdentitySelector {
    static let families: [[String]] = [
        ["Apple Development", "iPhone Developer", "Mac Developer"],
        ["Apple Distribution", "iPhone Distribution", "3rd Party Mac Developer Application", "Mac App Distribution"],
    ]

    public static func isHash(_ s: String) -> Bool {
        s.count == 40 && s.allSatisfy(\.isHexDigit)
    }

    public static func matches(_ selector: String, _ identity: SigningIdentity) -> Bool {
        if isHash(selector) { return selector.uppercased() == identity.hash }
        if selector == identity.name { return true }
        let kinds = families.first { $0.contains(selector) } ?? [selector]
        return kinds.contains(identity.kind)
    }

    public static func candidates(_ selector: String, team: String?, in identities: [SigningIdentity], now: Date) -> [SigningIdentity] {
        identities
            .filter { matches(selector, $0) && (team == nil || $0.team == team) && ($0.expires.map { $0 > now } ?? true) }
            .sorted { ($0.expires ?? .distantFuture) > ($1.expires ?? .distantFuture) }
    }

    public static func isDistribution(_ selector: String) -> Bool {
        families[1].contains(selector) || selector.hasPrefix("Developer ID")
    }
}

public struct CommandRunner: Sendable {
    public var run: @Sendable (_ executable: String, _ arguments: [String]) -> (status: Int32, output: Data)

    public init(run: @escaping @Sendable (String, [String]) -> (status: Int32, output: Data)) { self.run = run }

    public static let system = CommandRunner { executable, arguments in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data()) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }
}

public enum Keychain {
    public static let security = "/usr/bin/security"

    public static func parseFindIdentity(_ text: String) -> [(hash: String, name: String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let paren = t.firstIndex(of: ")"), Int(t[..<paren]) != nil else { continue }
            let rest = t[t.index(after: paren)...].trimmingCharacters(in: .whitespaces)
            guard let space = rest.firstIndex(of: " ") else { continue }
            let hash = String(rest[..<space])
            var name = rest[space...].trimmingCharacters(in: .whitespaces)
            guard IdentitySelector.isHash(hash), name.hasPrefix("\"") else { continue }
            name.removeFirst()
            guard let close = name.lastIndex(of: "\"") else { continue }
            if seen.insert(hash.uppercased()).inserted { out.append((hash.uppercased(), String(name[..<close]))) }
        }
        return out
    }

    public static func identities(runner: CommandRunner = .system) -> [SigningIdentity] {
        guard FileManager.default.isExecutableFile(atPath: security) else { return [] }
        let found = runner.run(security, ["find-identity", "-v", "-p", "codesigning"])
        guard found.status == 0 else { return [] }
        let listed = parseFindIdentity(String(decoding: found.output, as: UTF8.self))
        guard !listed.isEmpty else { return [] }
        let certs = runner.run(security, ["find-certificate", "-a", "-Z", "-p"])
        var summaries: [String: CertificateSummary] = [:]
        for block in CertificateSummary.pemBlocks(String(decoding: certs.output, as: UTF8.self)) {
            let hash = block.sha1 ?? SHA1.hex(block.der)
            if let s = CertificateSummary(der: block.der) { summaries[hash] = s }
        }
        return listed.map { item in
            let s = summaries[item.hash]
            return SigningIdentity(hash: item.hash, name: item.name, team: s?.organizationalUnit, expires: s?.notAfter)
        }
    }
}
