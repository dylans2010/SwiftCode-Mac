import Foundation

public enum ThreeWayMerge {
    public struct Chunk: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case unchanged
            case oursOnly
            case theirsOnly
            case bothSame
            case conflict
        }
        public var kind: Kind
        public var base: [String]
        public var ours: [String]
        public var theirs: [String]

        public init(kind: Kind, base: [String], ours: [String], theirs: [String]) {
            self.kind = kind
            self.base = base
            self.ours = ours
            self.theirs = theirs
        }
    }

    static func matches(_ base: [String], _ other: [String]) -> [Int?] {
        var out = [Int?](repeating: nil, count: base.count)
        var i = 0, j = 0
        for op in LineDiff.diff(base, other) {
            switch op {
            case .same: out[i] = j; i += 1; j += 1
            case .removed: i += 1
            case .added: j += 1
            }
        }
        return out
    }

    public static func merge(base: [String], ours: [String], theirs: [String]) -> [Chunk] {
        let mo = matches(base, ours), mt = matches(base, theirs)
        var chunks: [Chunk] = []
        var i = 0, j = 0, k = 0
        var stable: [String] = []
        func flushStable() {
            guard !stable.isEmpty else { return }
            chunks.append(Chunk(kind: .unchanged, base: stable, ours: stable, theirs: stable))
            stable = []
        }
        while true {
            while i < base.count, mo[i] == j, mt[i] == k {
                stable.append(base[i])
                i += 1; j += 1; k += 1
            }
            flushStable()
            if i == base.count, j == ours.count, k == theirs.count { break }
            var b = i
            while b < base.count, mo[b] == nil || mt[b] == nil { b += 1 }
            let jEnd = b < base.count ? mo[b]! : ours.count
            let kEnd = b < base.count ? mt[b]! : theirs.count
            let B = Array(base[i..<b]), O = Array(ours[j..<jEnd]), T = Array(theirs[k..<kEnd])
            let kind: Chunk.Kind
            if O == B, T == B { kind = .unchanged }
            else if O == B { kind = .theirsOnly }
            else if T == B { kind = .oursOnly }
            else if O == T { kind = .bothSame }
            else { kind = .conflict }
            if kind == .unchanged { stable += B; flushStable() } else { chunks.append(Chunk(kind: kind, base: B, ours: O, theirs: T)) }
            i = b; j = jEnd; k = kEnd
        }
        return coalesced(chunks)
    }

    static func coalesced(_ chunks: [Chunk]) -> [Chunk] {
        var out: [Chunk] = []
        for c in chunks {
            if c.kind == .unchanged, let last = out.last, last.kind == .unchanged {
                out[out.count - 1].base += c.base
                out[out.count - 1].ours += c.ours
                out[out.count - 1].theirs += c.theirs
            } else {
                out.append(c)
            }
        }
        return out
    }

    public static func compare(left: [String], right: [String]) -> [Chunk] {
        merge(base: left, ours: left, theirs: right)
    }
}

public enum ConflictMarkers {
    public struct Parsed: Equatable, Sendable {
        public var chunks: [ThreeWayMerge.Chunk]
        public var oursLabel: String?
        public var theirsLabel: String?
    }

    public static func hasConflicts(_ text: String) -> Bool { (parse(text)?.chunks.contains { $0.kind == .conflict }) ?? false }

    public static func parse(_ text: String) -> Parsed? {
        enum Section { case outside, ours, base, theirs }
        var out = Parsed(chunks: [])
        var section = Section.outside
        var plain: [String] = [], ours: [String] = [], base: [String] = [], theirs: [String] = []
        func flushPlain() {
            guard !plain.isEmpty else { return }
            out.chunks.append(.init(kind: .unchanged, base: plain, ours: plain, theirs: plain))
            plain = []
        }
        func marker(_ line: String, _ c: Character) -> String? {
            guard line.count >= 7, line.prefix(7).allSatisfy({ $0 == c }) else { return nil }
            let rest = line.dropFirst(7)
            if rest.isEmpty { return "" }
            guard rest.first == " " else { return nil }
            return String(rest.dropFirst())
        }
        for line in LineDiff.lines(text) {
            switch section {
            case .outside:
                if let label = marker(line, "<") {
                    flushPlain()
                    if out.oursLabel == nil { out.oursLabel = label.isEmpty ? nil : label }
                    section = .ours
                } else { plain.append(line) }
            case .ours:
                if marker(line, "|") != nil { section = .base }
                else if line == "=======" { section = .theirs }
                else { ours.append(line) }
            case .base:
                if line == "=======" { section = .theirs } else { base.append(line) }
            case .theirs:
                if let label = marker(line, ">") {
                    if out.theirsLabel == nil { out.theirsLabel = label.isEmpty ? nil : label }
                    let kind: ThreeWayMerge.Chunk.Kind = ours == theirs ? .bothSame : .conflict
                    out.chunks.append(.init(kind: kind, base: base, ours: ours, theirs: theirs))
                    ours = []; base = []; theirs = []
                    section = .outside
                } else { theirs.append(line) }
            }
        }
        guard section == .outside else { return nil }
        flushPlain()
        return out
    }
}

public struct MergeDocument: Equatable, Sendable {
    public enum Choice: Equatable, Sendable {
        case unresolved
        case ours, theirs, oursThenTheirs, theirsThenOurs, base
        case custom([String])
    }

    public private(set) var chunks: [ThreeWayMerge.Chunk]
    public private(set) var hunks: [Int]
    public private(set) var choices: [Choice]
    public var oursLabel: String
    public var theirsLabel: String
    public var baseLabel: String

    public init(chunks: [ThreeWayMerge.Chunk], oursLabel: String = "Ours", theirsLabel: String = "Theirs", baseLabel: String = "Base") {
        self.chunks = chunks
        hunks = chunks.indices.filter { chunks[$0].kind != .unchanged }
        choices = hunks.map { Self.defaultChoice(chunks[$0].kind) }
        self.oursLabel = oursLabel
        self.theirsLabel = theirsLabel
        self.baseLabel = baseLabel
    }

    public init(base: String, ours: String, theirs: String, oursLabel: String = "Ours", theirsLabel: String = "Theirs", baseLabel: String = "Base") {
        self.init(chunks: ThreeWayMerge.merge(base: LineDiff.lines(base), ours: LineDiff.lines(ours), theirs: LineDiff.lines(theirs)),
                  oursLabel: oursLabel, theirsLabel: theirsLabel, baseLabel: baseLabel)
    }

    public static func defaultChoice(_ kind: ThreeWayMerge.Chunk.Kind) -> Choice {
        switch kind {
        case .unchanged, .oursOnly, .bothSame: .ours
        case .theirsOnly: .theirs
        case .conflict: .unresolved
        }
    }

    public var conflictCount: Int { hunks.filter { chunks[$0].kind == .conflict }.count }
    public var unresolvedCount: Int { choices.filter { $0 == .unresolved }.count }
    public var isResolved: Bool { unresolvedCount == 0 }

    public mutating func choose(_ choice: Choice, hunk: Int) {
        guard choices.indices.contains(hunk) else { return }
        choices[hunk] = choice
    }

    public mutating func chooseAll(_ choice: Choice) {
        for h in choices.indices { choices[h] = choice }
    }

    public func step(from hunk: Int?, forward: Bool, unresolvedOnly: Bool = false) -> Int? {
        let candidates = choices.indices.filter { !unresolvedOnly || choices[$0] == .unresolved }
        guard !candidates.isEmpty else { return nil }
        guard let hunk else { return forward ? candidates.first : candidates.last }
        if forward { return candidates.first { $0 > hunk } ?? candidates.first }
        return candidates.last { $0 < hunk } ?? candidates.last
    }

    public func lines(forHunk h: Int) -> [String] {
        let c = chunks[hunks[h]]
        switch choices[h] {
        case .ours: return c.ours
        case .theirs: return c.theirs
        case .oursThenTheirs: return c.ours + c.theirs
        case .theirsThenOurs: return c.theirs + c.ours
        case .base: return c.base
        case .custom(let l): return l
        case .unresolved:
            return ["<<<<<<< " + oursLabel] + c.ours + ["======="] + c.theirs + [">>>>>>> " + theirsLabel]
        }
    }

    public func layout() -> (lines: [String], hunkRanges: [Range<Int>]) {
        var lines: [String] = []
        var ranges: [Range<Int>] = []
        var h = 0
        for (i, c) in chunks.enumerated() {
            if h < hunks.count, hunks[h] == i {
                let start = lines.count
                lines += self.lines(forHunk: h)
                ranges.append(start..<lines.count)
                h += 1
            } else {
                lines += c.base
            }
        }
        return (lines, ranges)
    }

    public var result: String {
        let l = layout().lines
        return l.isEmpty ? "" : l.joined(separator: "\n") + "\n"
    }

    public var oursText: String { Self.text(chunks.flatMap(\.ours)) }
    public var theirsText: String { Self.text(chunks.flatMap(\.theirs)) }
    public var baseText: String { Self.text(chunks.flatMap(\.base)) }
    static func text(_ l: [String]) -> String { l.isEmpty ? "" : l.joined(separator: "\n") + "\n" }

    public func sideStarts(forHunk h: Int) -> (base: Int, ours: Int, theirs: Int) {
        var b = 0, o = 0, t = 0
        for c in chunks[..<hunks[h]] { b += c.base.count; o += c.ours.count; t += c.theirs.count }
        return (b, o, t)
    }
}
