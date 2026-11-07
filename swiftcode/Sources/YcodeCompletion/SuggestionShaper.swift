import Foundation

public struct SuggestionShaper: Sendable {
    public var maxLines: Int
    public init(maxLines: Int = 12) { self.maxLines = max(1, maxLines) }

    public struct Result: Sendable, Equatable {
        public var text: String
        public var complete: Bool
    }

    public func shape(_ raw: String, context c: CompletionContext, final: Bool = true, fromChat: Bool = false) -> Result {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if fromChat { text = Self.unfence(text, linePrefix: c.linePrefix) }
        let (cut, complete) = cutAtBoundary(text, context: c, final: final)
        guard complete || final else {
            return Result(text: Self.reject(cut, c) ? "" : Self.trimTrailing(cut), complete: false)
        }
        var t = trimOverlap(cut, c)
        t = Self.trimTrailing(t)
        return Result(text: Self.reject(t, c) ? "" : t, complete: true)
    }

    func cutAtBoundary(_ text: String, context c: CompletionContext, final: Bool) -> (String, Bool) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let completeCount = final ? lines.count : lines.count - 1
        if c.isMidLine {
            if lines.count > 1 { return (lines[0], true) }
            return (text, final)
        }
        let base = Self.indent(c.linePrefix)
        var kept: [String] = []
        var depth = 0
        var blankRun = 0
        let open = max(0, Self.bracketDelta(c.linePrefix))
        for (i, line) in lines.enumerated() {
            let isComplete = i < completeCount
            if i > 0, line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { return (Self.dropTrailingBlank(kept), true) }
            if i > 0 {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    blankRun += 1
                    if blankRun >= 2 && isComplete { return (kept.joined(separator: "\n"), true) }
                } else {
                    blankRun = 0
                    if Self.indent(line) < base && (isComplete || line.count > Self.indent(line)) { return (Self.dropTrailingBlank(kept), true) }
                }
            }
            if kept.count >= maxLines { return (Self.dropTrailingBlank(kept), true) }
            kept.append(line)
            guard isComplete else { break }
            let before = depth
            depth += Self.bracketDelta(line)
            if i > 0, Self.startsWithCloser(line), depth < 0 || (before > 0 && depth == 0) { return (kept.joined(separator: "\n"), true) }
            if open > 0, open + before > 0, open + depth <= 0 { return (kept.joined(separator: "\n"), true) }
        }
        return (kept.joined(separator: "\n"), final)
    }

    func trimOverlap(_ s: String, _ c: CompletionContext) -> String {
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let following = c.suffixAfterLine.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 && !following.isEmpty {
            for m in stride(from: min(lines.count - 1, following.count, 8), through: 1, by: -1) {
                let tail = lines.suffix(m).map { $0.trimmingCharacters(in: .whitespaces) }
                if tail.allSatisfy({ !$0.isEmpty }) && Array(tail) == Array(following.prefix(m)) {
                    lines.removeLast(m)
                    break
                }
            }
        }
        if lines.count == 1, var last = lines.last {
            let rest = c.lineSuffix.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                for k in stride(from: min(rest.count, last.count), through: 1, by: -1) where last.hasSuffix(String(rest.prefix(k))) {
                    last.removeLast(k)
                    break
                }
                lines[0] = last
            }
        }
        return lines.joined(separator: "\n")
    }

    static func reject(_ s: String, _ c: CompletionContext) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let after = c.suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if after.hasPrefix(t) { return true }
        let previous = c.prefix.split(separator: "\n", omittingEmptySubsequences: true).dropLast(c.linePrefix.isEmpty ? 0 : 1).last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let lines = t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let p = previous, !p.isEmpty, lines.allSatisfy({ $0 == p }), c.linePrefix.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    static func unfence(_ s: String, linePrefix: String) -> String {
        var t = s
        if let open = t.range(of: "```") {
            var body = t[open.upperBound...]
            if let nl = body.firstIndex(of: "\n") { body = body[body.index(after: nl)...] }
            if let close = body.range(of: "```") { body = body[..<close.lowerBound] }
            t = String(body)
            if t.hasSuffix("\n") { t.removeLast() }
        }
        t = t.replacingOccurrences(of: "<CURSOR>", with: "")
        let lead = String(linePrefix.drop { $0 == " " || $0 == "\t" })
        let bare = lead.trimmingCharacters(in: .whitespaces)
        let stripped = String(t.drop { $0 == " " || $0 == "\t" })
        if !lead.isEmpty, stripped.hasPrefix(lead) {
            t = String(stripped.dropFirst(lead.count))
        } else if !bare.isEmpty, stripped.hasPrefix(bare) {
            t = String(stripped.dropFirst(bare.count))
            if lead.hasSuffix(" "), t.hasPrefix(" ") { t.removeFirst() }
        }
        return t
    }

    static func indent(_ line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 } else if ch == "\t" { n += 4 } else { break }
        }
        return n
    }

    static func bracketDelta(_ line: String) -> Int {
        var d = 0
        var quote: Character?
        var prev: Character = " "
        for ch in line {
            if let q = quote {
                if ch == q && prev != "\\" { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if "([{".contains(ch) {
                d += 1
            } else if ")]}".contains(ch) {
                d -= 1
            } else if ch == "/" && prev == "/" {
                break
            }
            prev = ch
        }
        return d
    }

    static func startsWithCloser(_ line: String) -> Bool {
        guard let f = line.trimmingCharacters(in: .whitespaces).first else { return false }
        return ")]}".contains(f)
    }

    static func dropTrailingBlank(_ lines: [String]) -> String {
        var l = lines
        while let last = l.last, last.trimmingCharacters(in: .whitespaces).isEmpty, l.count > 1 { l.removeLast() }
        return l.joined(separator: "\n")
    }

    static func trimTrailing(_ s: String) -> String {
        var t = s
        while let last = t.last, last == "\n" || last == " " || last == "\t" { t.removeLast() }
        return t
    }
}
