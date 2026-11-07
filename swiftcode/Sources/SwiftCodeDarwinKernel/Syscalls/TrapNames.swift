public enum TrapNames {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var argumentNames: [String]
    }

    private static func parse(_ table: String) -> [Entry] {
        table.split(separator: ";", omittingEmptySubsequences: false).map { item in
            let parts = item.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let args = parts.count > 1 && !parts[1].isEmpty ? parts[1].split(separator: ",").map(String.init) : []
            return Entry(name: String(parts[0]), argumentNames: args)
        }
    }

    public static let bsd: [Entry] = parse(GeneratedTrapNames.bsd)
    public static let mach: [Entry] = parse(GeneratedTrapNames.mach)

    public static func bsd(_ number: Int) -> Entry {
        bsd.indices.contains(number) ? bsd[number] : bsd[63]
    }

    public static func mach(_ number: Int) -> Entry {
        let index = -number
        return mach.indices.contains(index) ? mach[index] : Entry(name: "kern_invalid", argumentNames: [])
    }

    static func describe(_ entry: Entry, _ args: [UInt64]) -> String {
        let shown = entry.argumentNames.enumerated().map { i, n in "\(n)=\(hx(i < args.count ? args[i] : 0))" }
        return "\(entry.name)(\(shown.joined(separator: ", ")))"
    }
}
