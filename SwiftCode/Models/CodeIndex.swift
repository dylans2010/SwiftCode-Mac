import Foundation

// MARK: - Index Entry

struct IndexEntry: Identifiable {
    let id = UUID()
    let name: String
    let kind: SymbolKind
    let filePath: String
    let lineNumber: Int
    let snippet: String

    enum SymbolKind: String, CaseIterable {
        case function = "func"
        case structType = "struct"
        case classType = "class"
        case enumType = "enum"
        case variable = "var"
        case constant = "let"
        case importDecl = "import"
        case protocolType = "protocol"
        case extensionType = "extension"

        var icon: String {
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

        var color: String {
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

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let lineNumber: Int
    let snippet: String
    let matchRange: Range<String.Index>?
}

// MARK: - Code Error

struct CodeError: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let lineNumber: Int
    let message: String
    let severity: Severity
    let source: ErrorSource

    enum Severity: String {
        case error = "Error"
        case warning = "Warning"
        case info = "Info"

        var icon: String {
            switch self {
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    enum ErrorSource: String {
        case syntaxAnalysis = "Syntax Analysis"
        case aiReview = "AI Review"
        case buildLog = "Build Log"
    }
}

// MARK: - Package Dependency

struct PackageDependency: Identifiable, Codable {
    var id = UUID()
    var name: String
    var url: String
    var version: String
    var source: DependencySource

    enum DependencySource: String, Codable, CaseIterable {
        case github = "GitHub"
        case swiftPackageIndex = "Swift Package Index"
        case gitURL = "Git URL"
    }

    var packageSwiftEntry: String {
        ".package(url: \"\(url)\", from: \"\(version)\")"
    }
}
