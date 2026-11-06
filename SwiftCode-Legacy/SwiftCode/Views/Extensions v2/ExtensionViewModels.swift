import Foundation
import SwiftUI

// MARK: - Extensions v2 view models
//
// View models translate manager state into what a view shows. They own
// no install state themselves: every action goes through ExtV2Manager,
// and every list re-reads from it, so the UI can never drift from the
// authoritative records.

public enum ExtV2HomeSection: String, CaseIterable, Identifiable {
    case discover, installed, updates, enabled, disabled, native, xcode, permissions, settings, diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .discover: return "Discover"
        case .installed: return "Installed"
        case .updates: return "Updates"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .native: return "Native Extensions"
        case .xcode: return "Xcode Compatibility"
        case .permissions: return "Permissions"
        case .settings: return "Settings"
        case .diagnostics: return "Diagnostics"
        }
    }

    public var icon: String {
        switch self {
        case .discover: return "magnifyingglass"
        case .installed: return "square.stack"
        case .updates: return "arrow.down.circle"
        case .enabled: return "checkmark.circle"
        case .disabled: return "pause.circle"
        case .native: return "swift"
        case .xcode: return "hammer"
        case .permissions: return "lock"
        case .settings: return "gear"
        case .diagnostics: return "stethoscope"
        }
    }
}

@MainActor
public final class ExtV2HomeViewModel: ObservableObject {
    @Published public var section: ExtV2HomeSection = .discover
    @Published public var searchText = ""
    @Published public var selectedInstalled: ExtV2InstalledExtension?
    @Published public var selectedSearchResult: ExtV2ExtensionMetadata?

    public let manager = ExtV2Manager.shared

    public init() {}

    public var filteredInstalled: [ExtV2InstalledExtension] {
        switch section {
        case .enabled: return manager.installed.filter { $0.isEnabled }
        case .disabled: return manager.installed.filter { !$0.isEnabled }
        case .native: return manager.installed.filter { $0.metadata.kind == .native }
        case .installed, .discover, .updates, .xcode, .permissions, .settings, .diagnostics: return manager.installed
        }
    }

    public func search() {
        manager.search(query: searchText)
    }
}

@MainActor
public final class ExtV2RunViewModel: ObservableObject {
    public enum State {
        case loading
        case ready(ExtV2Contribution)
        case failed(String)
    }

    @Published public private(set) var state: State = .loading
    @Published public var commandResult: String?
    @Published public var isExecuting = false

    public let extensionId: String
    public let manager = ExtV2Manager.shared

    public init(extensionId: String) {
        self.extensionId = extensionId
    }

    public func activate() async {
        state = .loading
        do {
            let contribution = try await manager.activate(extensionId: extensionId)
            state = .ready(contribution)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func execute(command: String) async {
        isExecuting = true
        defer { isExecuting = false }
        do {
            commandResult = try await manager.executeCommand(extensionId: extensionId, command: command)
        } catch {
            commandResult = "Failed: \(error.localizedDescription)"
        }
    }

    public func deactivate() {
        manager.deactivate(extensionId: extensionId)
    }
}

@MainActor
public final class ExtV2DetailsViewModel: ObservableObject {
    public let installed: ExtV2InstalledExtension
    public let compatibility: ExtV2CompatibilityReport?

    public init(installed: ExtV2InstalledExtension) {
        self.installed = installed
        if installed.metadata.kind == .vscode,
           let manifest = try? ExtV2ManifestParser.parseFile(
            at: URL(fileURLWithPath: installed.installPath).appendingPathComponent("extension/package.json")) {
            self.compatibility = ExtV2Compatibility.evaluate(manifest: manifest)
        } else {
            self.compatibility = nil
        }
    }
}

@MainActor
public final class ExtV2DiagnosticsViewModel: ObservableObject {
    @Published public private(set) var entries: [ExtV2DiagnosticEntry] = []

    public init() {}

    public func refresh() {
        entries = ExtV2DiagnosticsService.shared.allEntries().reversed()
    }

    public func clear() {
        ExtV2DiagnosticsService.shared.clear()
        entries = []
    }
}
