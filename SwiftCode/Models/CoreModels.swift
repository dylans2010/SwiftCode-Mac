import Foundation

// MARK: - Code Error

public struct CodeError: Identifiable, Sendable {
    public let id = UUID()
    public let fileName: String
    public let filePath: String
    public let lineNumber: Int
    public let message: String
    public let severity: Severity
    public let source: ErrorSource

    public init(fileName: String, filePath: String, lineNumber: Int, message: String, severity: Severity, source: ErrorSource) {
        self.fileName = fileName
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.message = message
        self.severity = severity
        self.source = source
    }

    public enum Severity: String, Sendable {
        case error = "Error"
        case warning = "Warning"
        case info = "Info"

        public var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    public enum ErrorSource: String, Sendable {
        case syntaxAnalysis = "Syntax Analysis"
        case aiReview = "AI Review"
        case buildLog = "Build Log"
    }
}

// MARK: - Search Result

public struct SearchResult: Identifiable, Codable, Sendable {
    public let id: UUID
    public let fileName: String
    public let filePath: String
    public let lineNumber: Int
    public let snippet: String
    public let matchRange: Range<String.Index>?

    public init(id: UUID = UUID(), fileName: String? = nil, filePath: String, lineNumber: Int, snippet: String, matchRange: Range<String.Index>? = nil) {
        self.id = id
        self.fileName = fileName ?? URL(fileURLWithPath: filePath).lastPathComponent
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.snippet = snippet
        self.matchRange = matchRange
    }

    public var lineContent: String {
        snippet
    }
}

// MARK: - Index Entry

public struct IndexEntry: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let kind: SymbolKind
    public let filePath: String
    public let lineNumber: Int
    public let snippet: String

    public init(name: String, kind: SymbolKind, filePath: String, lineNumber: Int, snippet: String) {
        self.name = name
        self.kind = kind
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.snippet = snippet
    }

    public enum SymbolKind: String, CaseIterable, Sendable {
        case function = "func"
        case structType = "struct"
        case classType = "class"
        case enumType = "enum"
        case variable = "var"
        case constant = "let"
        case importDecl = "import"
        case protocolType = "protocol"
        case extensionType = "extension"

        public var icon: String {
            switch self {
            case .function: return "f.circle.fill"
            case .structType: return "s.circle.fill"
            case .classType: return "c.circle.fill"
            case .enumType: return "e.circle.fill"
            case .variable: return "v.circle.fill"
            case .constant: return "l.circle.fill"
            case .importDecl: return "arrow.down.circle.fill"
            case .protocolType: return "p.circle.fill"
            case .extensionType: return "curlybraces"
            }
        }

        public var color: String {
            switch self {
            case .function: return "purple"
            case .structType: return "blue"
            case .classType: return "yellow"
            case .enumType: return "green"
            case .variable: return "cyan"
            case .constant: return "teal"
            case .importDecl: return "gray"
            case .protocolType: return "orange"
            case .extensionType: return "indigo"
            }
        }
    }
}
