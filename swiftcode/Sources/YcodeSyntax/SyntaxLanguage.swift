import Foundation

public enum SyntaxLanguage: String, Sendable, CaseIterable, Hashable {
    case swift, objc, c, plain
    case cpp, metal, json, xml, markdown, yaml, shell, xcconfig

    public init(fileName: String) {
        let url = URL(fileURLWithPath: fileName)
        let name = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "swift", "swiftinterface": self = .swift
        case "m", "mm", "h", "pch": self = .objc
        case "c": self = .c
        case "cc", "cpp", "cxx", "c++", "hpp", "hh", "hxx", "ipp", "tpp", "inl", "modulemap": self = .cpp
        case "metal": self = .metal
        case "json", "jsonc", "geojson", "xcstrings", "xcactivitylog-json", "resolved", "swiftcodetheme": self = .json
        case "xml", "plist", "entitlements", "xib", "storyboard", "xcscheme", "xcworkspacedata", "xcsettings", "svg",
             "xcplayground", "xcbkptlist", "html", "htm", "xhtml", "xliff", "xlf", "strings-xml", "sdef", "intentdefinition",
             "xccheckout", "xcscmblueprint", "dae", "rss", "atom":
            self = .xml
        case "md", "markdown", "mdown", "mkd", "docc": self = .markdown
        case "yml", "yaml": self = .yaml
        case "sh", "bash", "zsh", "ksh", "command", "tool": self = .shell
        case "xcconfig": self = .xcconfig
        default:
            switch name {
            case "Package.resolved": self = .json
            case ".bashrc", ".zshrc", ".profile", ".bash_profile", ".zprofile", "Makefile.sh": self = .shell
            case ".swiftlint.yml", ".clang-format": self = .yaml
            default: self = .plain
            }
        }
    }

    public var displayName: String {
        switch self {
        case .swift: "Swift"
        case .objc: "Objective-C"
        case .c: "C"
        case .plain: "None"
        case .cpp: "C++"
        case .metal: "Metal"
        case .json: "JSON"
        case .xml: "XML"
        case .markdown: "Markdown"
        case .yaml: "YAML"
        case .shell: "Shell Script"
        case .xcconfig: "Build Configuration File"
        }
    }

    public var isCFamily: Bool { self == .c || self == .cpp || self == .objc || self == .metal }

    public var isCode: Bool { self == .swift || isCFamily }

    public enum CommentStyle: Equatable, Sendable {
        case line(String)
        case block(String, String)
    }

    public var commentStyle: CommentStyle? {
        switch self {
        case .swift, .objc, .c, .cpp, .metal, .json, .xcconfig: .line("//")
        case .yaml, .shell: .line("#")
        case .xml, .markdown: .block("<!--", "-->")
        case .plain: nil
        }
    }

    public static let bracketPairs: [(open: Character, close: Character)] = [("(", ")"), ("[", "]"), ("{", "}")]

    public var quotes: [Character] {
        switch self {
        case .swift: ["\""]
        case .objc, .c, .cpp, .metal: ["\"", "'"]
        case .json, .xcconfig: ["\""]
        case .xml: ["\"", "'"]
        case .markdown: ["`"]
        case .yaml: ["\"", "'"]
        case .shell: ["\"", "'", "`"]
        case .plain: ["\""]
        }
    }
}
