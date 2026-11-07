import Foundation

public struct DiagnosticParser: Sendable {
    public private(set) var finished: [Diagnostic] = []
    private var pending: Diagnostic?
    private var seen: Set<Diagnostic> = []

    public init() {}

    @discardableResult
    public mutating func feed(_ line: String) -> [Diagnostic] {
        if let fix = Self.parseFixIt(line) {
            pending?.fixIts.append(fix)
            return []
        }
        guard let d = Self.parseLine(line) else { return [] }
        if d.severity == .note, pending != nil {
            pending!.notes.append(d)
            return []
        }
        let done = flush()
        pending = d
        return done
    }

    public mutating func finish() -> [Diagnostic] { flush() }

    private mutating func flush() -> [Diagnostic] {
        guard let p = pending else { return [] }
        pending = nil
        guard seen.insert(p).inserted else { return [] }
        finished.append(p)
        return [p]
    }

    public static func parse(_ text: String) -> [Diagnostic] {
        var p = DiagnosticParser()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            p.feed(String(line.hasSuffix("\r") ? line.dropLast() : line))
        }
        _ = p.finish()
        return p.finished
    }

    public static func parseLine(_ line: String) -> Diagnostic? {
        for severity in Diagnostic.Severity.allCases {
            let tag = "\(severity.rawValue): "
            if line.hasPrefix(tag) {
                return Diagnostic(severity: severity, message: String(line.dropFirst(tag.count)))
            }
        }
        var best: (Range<String.Index>, Diagnostic.Severity)?
        for severity in Diagnostic.Severity.allCases {
            if let r = line.range(of: ": \(severity.rawValue): "), best == nil || r.lowerBound < best!.0.lowerBound {
                best = (r, severity)
            }
        }
        guard let (range, severity) = best else { return nil }
        let prefix = String(line[..<range.lowerBound])
        let message = String(line[range.upperBound...])
        guard !prefix.isEmpty, !prefix.hasPrefix(" ") else { return nil }
        return Diagnostic(severity: severity, message: message, location: location(prefix))
    }

    static func location(_ prefix: String) -> Diagnostic.Location? {
        var parts = prefix.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var numbers: [Int] = []
        while numbers.count < 2, parts.count > 1, let n = Int(parts.last!) {
            numbers.insert(n, at: 0)
            parts.removeLast()
        }
        let file = parts.joined(separator: ":")
        if numbers.isEmpty {
            guard file.contains("/") || file.contains(".") else { return nil }
            return .init(file: file, line: 0)
        }
        return .init(file: file, line: numbers[0], column: numbers.count > 1 ? numbers[1] : 0)
    }

    public static func parseFixIt(_ line: String) -> Diagnostic.FixIt? {
        guard line.hasPrefix("fix-it:\"") else { return nil }
        var rest = line.dropFirst("fix-it:\"".count)
        guard let q = rest.range(of: "\":{") else { return nil }
        let file = String(rest[..<q.lowerBound])
        rest = rest[q.upperBound...]
        guard let close = rest.range(of: "}:\"") else { return nil }
        let nums = rest[..<close.lowerBound].split(whereSeparator: { $0 == ":" || $0 == "-" }).compactMap { Int($0) }
        guard nums.count == 4, rest.hasSuffix("\"") else { return nil }
        let text = unescapeC(String(rest[close.upperBound...].dropLast()))
        return .init(file: file,
                     start: .init(file: file, line: nums[0], column: nums[1]),
                     end: .init(file: file, line: nums[2], column: nums[3]),
                     replacement: text)
    }

    private static func unescapeC(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            default: out.append(n)
            }
        }
        return out
    }
}
