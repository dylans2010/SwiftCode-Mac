import Foundation

public struct ExtV2ContributionCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String
}

public struct ExtV2ContributionView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public struct ExtV2TreeItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let command: String?
}

public struct ExtV2Contribution: Codable, Sendable {
    public let commands: [ExtV2ContributionCommand]
    public let views: [ExtV2ContributionView]
    public let treeItems: [ExtV2TreeItem]
    public let statusBarText: String?
    public let outputLines: [String]
    public let webviewHTML: String?

    public init(
        commands: [ExtV2ContributionCommand] = [], views: [ExtV2ContributionView] = [],
        treeItems: [ExtV2TreeItem] = [], statusBarText: String? = nil,
        outputLines: [String] = [], webviewHTML: String? = nil
    ) {
        self.commands = commands
        self.views = views
        self.treeItems = treeItems
        self.statusBarText = statusBarText
        self.outputLines = outputLines
        self.webviewHTML = webviewHTML
    }

    public static let empty = ExtV2Contribution()
}

public struct ExtV2Diagnostic: Codable, Hashable, Sendable {
    public let relativePath: String
    public let range: ExtV2TextRange
    public let message: String
    public let severity: String
    public let source: String
}

@MainActor
public final class ExtV2ProviderRegistry: ObservableObject {
    public static let shared = ExtV2ProviderRegistry()

    @Published public private(set) var diagnostics: [String: [ExtV2Diagnostic]] = [:]
    @Published public private(set) var completionProviders: [String: String] = [:]
    @Published public private(set) var hoverProviders: [String: String] = [:]

    public init() {}

    public func publishDiagnostics(extensionId: String, relativePath: String, diagnostics: [ExtV2Diagnostic]) {
        self.diagnostics[relativePath] = diagnostics
        ExtV2DiagnosticsService.shared.info("Published \(diagnostics.count) diagnostics for \(relativePath)", extensionId: extensionId)
    }

    public func registerCompletionProvider(extensionId: String, language: String) {
        completionProviders[language] = extensionId
    }

    public func registerHoverProvider(extensionId: String, language: String) {
        hoverProviders[language] = extensionId
    }

    public func clear(for extensionId: String) {
        diagnostics = diagnostics.mapValues { $0.filter { $0.source != extensionId } }
            .filter { !$0.value.isEmpty }
        completionProviders = completionProviders.filter { $0.value != extensionId }
        hoverProviders = hoverProviders.filter { $0.value != extensionId }
    }
}

public enum ExtV2UnsupportedVSCodeAPIs {
    public static let all: [String] = [
        "vscode.debug", "vscode.notebooks", "vscode.tests",
        "vscode.authentication", "vscode.SecretStorage",
        "vscode.CustomEditor", "vscode.FileSystemProvider",
        "vscode.Terminal.createTerminal (full PTY)",
    ]
}
