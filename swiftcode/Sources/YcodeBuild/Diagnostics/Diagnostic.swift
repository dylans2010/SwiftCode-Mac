import Foundation

public struct Diagnostic: Equatable, Sendable, Hashable {
    public enum Severity: String, Sendable, Hashable, CaseIterable {
        case error, warning, note, remark
    }

    public struct Location: Equatable, Sendable, Hashable {
        public var file: String
        public var line: Int
        public var column: Int
        public init(file: String, line: Int, column: Int = 0) {
            self.file = file
            self.line = line
            self.column = column
        }
    }

    public struct FixIt: Equatable, Sendable, Hashable {
        public var file: String
        public var start: Location
        public var end: Location
        public var replacement: String
        public init(file: String, start: Location, end: Location, replacement: String) {
            self.file = file
            self.start = start
            self.end = end
            self.replacement = replacement
        }
    }

    public var severity: Severity
    public var message: String
    public var location: Location?
    public var notes: [Diagnostic]
    public var fixIts: [FixIt]

    public init(severity: Severity, message: String, location: Location? = nil, notes: [Diagnostic] = [], fixIts: [FixIt] = []) {
        self.severity = severity
        self.message = message
        self.location = location
        self.notes = notes
        self.fixIts = fixIts
    }
}

extension Diagnostic: CustomStringConvertible {
    public var description: String {
        var s = ""
        if let l = location {
            s = "\(l.file):\(l.line):"
            if l.column > 0 { s += "\(l.column):" }
            s += " "
        }
        return s + "\(severity.rawValue): \(message)"
    }
}
