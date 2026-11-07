import Foundation

public enum EntitlementPolicy {
    public static let derivedKeys: Set<String> = [
        "application-identifier", "com.apple.application-identifier", "com.apple.developer.team-identifier",
        "get-task-allow", "com.apple.security.get-task-allow",
    ]

    public static func isRestricted(_ key: String, on platform: SigningPlatform) -> Bool {
        switch platform {
        case .simulator: false
        case .macOS, .macCatalyst: !key.hasPrefix("com.apple.security.")
        case .device: key != "get-task-allow"
        }
    }

    public static func pattern(_ pattern: String, matches value: String) -> Bool {
        let p = Array(pattern), v = Array(value)
        var pi = 0, vi = 0, star = -1, mark = 0
        while vi < v.count {
            if pi < p.count, p[pi] == "*" { star = pi; mark = vi; pi += 1 }
            else if pi < p.count, p[pi] == v[vi] { pi += 1; vi += 1 }
            else if star >= 0 { pi = star + 1; mark += 1; vi = mark }
            else { return false }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    public static func allows(_ allowed: EntitlementValue, _ requested: EntitlementValue) -> Bool {
        switch (allowed, requested) {
        case (.bool(let a), .bool(let r)): return a || !r
        case (.string(let a), .string(let r)): return pattern(a, matches: r)
        case (.string(let a), .array(let r)):
            return r.allSatisfy { $0.stringValue.map { pattern(a, matches: $0) } ?? false }
        case (.array(let a), .string(let r)):
            return a.contains { $0.stringValue.map { pattern($0, matches: r) } ?? false }
        case (.array(let a), .array(let r)):
            return r.allSatisfy { item in
                a.contains { allowedItem in
                    if let p = allowedItem.stringValue, let s = item.stringValue { return pattern(p, matches: s) }
                    return allowedItem == item
                }
            }
        default: return allowed == requested
        }
    }

    public enum Mismatch: Equatable, Sendable {
        case missing(String)
        case value(String)
    }

    public static func mismatches(_ requested: Entitlements, profile: ProvisioningProfile, platform: SigningPlatform) -> [Mismatch] {
        requested.keys.sorted().compactMap { key in
            guard isRestricted(key, on: platform), !derivedKeys.contains(key), let value = requested[key] else { return nil }
            guard let allowed = profile.entitlements[key] else { return .missing(key) }
            return allows(allowed, value) ? nil : .value(key)
        }
    }

    public static func restrictedKeys(_ e: Entitlements, on platform: SigningPlatform) -> [String] {
        e.keys.filter { isRestricted($0, on: platform) && !derivedKeys.contains($0) }.sorted()
    }
}
