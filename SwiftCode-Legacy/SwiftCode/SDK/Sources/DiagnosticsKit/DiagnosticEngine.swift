import Foundation

public protocol DiagnosticRule: Sendable {
    var id: String { get }
    var description: String { get }
    func evaluate(context: DiagnosticContext) -> [Diagnostic]
}

public struct DiagnosticContext: Sendable {
    public let targetPath: String
    public let files: [String]
    public let metadata: [String: String]

    public init(targetPath: String, files: [String] = [], metadata: [String: String] = [:]) {
        self.targetPath = targetPath
        self.files = files
        self.metadata = metadata
    }
}

public final class DiagnosticEngine: @unchecked Sendable {
    private var diagnostics: [Diagnostic] = []
    private var rules: [DiagnosticRule] = []
    private let lock = NSLock()

    public init(rules: [DiagnosticRule] = []) {
        self.rules = rules
    }

    public func register(rule: DiagnosticRule) {
        lock.lock()
        defer { lock.unlock() }
        rules.append(rule)
    }

    public func emit(_ diagnostic: Diagnostic) {
        lock.lock()
        defer { lock.unlock() }
        diagnostics.append(diagnostic)
    }

    public func emit(
        code: DiagnosticCode,
        severity: DiagnosticSeverity,
        message: String,
        location: DiagnosticLocation? = nil,
        remediation: String? = nil,
        metadata: [String: String] = [:]
    ) {
        emit(Diagnostic(
            code: code,
            severity: severity,
            message: message,
            location: location,
            remediation: remediation,
            metadata: metadata
        ))
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        diagnostics.removeAll()
    }

    public var allDiagnostics: [Diagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics
    }

    public var hasErrors: Bool {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics.contains { $0.severity == .error }
    }

    public var errorCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics.filter { $0.severity == .warning }.count
    }

    public func runRules(on context: DiagnosticContext) -> [Diagnostic] {
        var results: [Diagnostic] = []
        for rule in rules {
            results.append(contentsOf: rule.evaluate(context: context))
        }
        for d in results {
            emit(d)
        }
        return results
    }
}

public enum DiagnosticFormatter {
    public static func formatText(_ diagnostics: [Diagnostic]) -> String {
        if diagnostics.isEmpty {
            return "No diagnostics reported."
        }
        var lines: [String] = []
        for d in diagnostics.sorted(by: { $0.severity > $1.severity }) {
            var prefix = "\(d.severity.symbol) [\(d.code.rawValue)] [\(d.severity.rawValue.uppercased())]"
            if let loc = d.location {
                prefix += " at \(loc.formattedDescription)"
            }
            lines.append("\(prefix): \(d.message)")
            if let rem = d.remediation {
                lines.append("   Suggestion: \(rem)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func formatJSON(_ diagnostics: [Diagnostic]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(diagnostics)
        return String(decoding: data, as: UTF8.self)
    }
}
