import Foundation

// MARK: - VS Code API surface, Swift side
//
// This file owns three things and nothing else:
//  1. The contribution model a host activation returns (commands, views,
//     tree items, status bar, output) — the only UI a host may produce.
//  2. Provider registries (completion, hover, definition, formatting,
//     diagnostics) that the editor bridges consult.
//  3. The explicit list of what is NOT implemented, so the UI never
//     renders a contribution type with no backing implementation.

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
    /// HTML for a supported webview contribution, if any. Rendered only
    /// through the restricted WKWebView bridge in ExtensionRunView.
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

/// A diagnostic published by an extension, rendered in the editor's
/// diagnostics surfaces through the same model the app already uses for
/// its own diagnostics (message + range + severity, no host objects).
public struct ExtV2Diagnostic: Codable, Hashable, Sendable {
    public let relativePath: String
    public let range: ExtV2TextRange
    public let message: String
    public let severity: String
    public let source: String
}

/// Provider registries. A host registers providers by sending IPC
/// notifications; the Swift side stores plain data + the owning
/// extension id, and the editor consults these before its own providers.
/// No host code runs inside the editor process.
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

/// APIs the host shim deliberately does not implement. The host script
/// throws a descriptive error for these instead of returning success.
public enum ExtV2UnsupportedVSCodeAPIs {
    public static let all: [String] = [
        "vscode.debug", "vscode.notebooks", "vscode.tests",
        "vscode.authentication", "vscode.SecretStorage",
        "vscode.CustomEditor", "vscode.FileSystemProvider",
        "vscode.Terminal.createTerminal (full PTY)",
    ]
}
