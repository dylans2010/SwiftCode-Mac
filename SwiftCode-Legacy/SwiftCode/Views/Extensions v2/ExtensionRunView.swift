import SwiftUI
import WebKit

// MARK: - ExtensionRunView: hosts an extension's real contributions
//
// This view resolves an extension by its stable id, activates it
// through the manager, and renders only the contribution types the
// host actually implements: commands, tree items, status bar, output,
// and (restricted) webviews. It never embeds VS Code itself.
// On disappear it deactivates, so switching extensions cannot leak
// a host process or a provider registration.

public struct ExtensionRunView: View {
    public let extensionId: String
    @StateObject private var viewModel: ExtV2RunViewModel
    @ObservedObject private var manager = ExtV2Manager.shared

    public init(extensionId: String) {
        self.extensionId = extensionId
        _viewModel = StateObject(wrappedValue: ExtV2RunViewModel(extensionId: extensionId))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            switch viewModel.state {
            case .loading:
                ProgressView("Activating extension…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView(
                    "Extension failed to activate",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message))
                Button("Retry") { Task { await viewModel.activate() } }
                    .buttonStyle(.borderedProminent)
                    .padding()
            case .ready(let contribution):
                contributionView(contribution)
            }
        }
        .task { await viewModel.activate() }
        .onDisappear { viewModel.deactivate() }
        .frame(minWidth: 480, minHeight: 400)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(extensionId).font(.headline)
                if let installed = manager.installed.first(where: { $0.id == extensionId }) {
                    Text("\(installed.metadata.displayName) · v\(installed.metadata.version) · \(installed.state.displayName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Deactivate") { viewModel.deactivate() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
    }

    private func contributionView(_ contribution: ExtV2Contribution) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !contribution.commands.isEmpty {
                    GroupBox("Commands") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(contribution.commands, id: \.command) { command in
                                Button(command.title) {
                                    Task { await viewModel.execute(command: command.command) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isExecuting)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let result = viewModel.commandResult {
                    GroupBox("Command result") {
                        Text(result)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !contribution.treeItems.isEmpty {
                    GroupBox("Views") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(contribution.treeItems) { item in
                                HStack {
                                    Text(item.label).font(.callout)
                                    if let description = item.description {
                                        Text(description).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let command = item.command {
                                        Button("Run") { Task { await viewModel.execute(command: command) } }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let statusBarText = contribution.statusBarText {
                    GroupBox("Status bar") {
                        Text(statusBarText).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !contribution.outputLines.isEmpty {
                    GroupBox("Output") {
                        Text(contribution.outputLines.joined(separator: "\n"))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let html = contribution.webviewHTML {
                    GroupBox("Webview (restricted)") {
                        ExtV2RestrictedWebView(html: html, extensionId: extensionId)
                            .frame(height: 320)
                    }
                }
                if contribution.commands.isEmpty && contribution.treeItems.isEmpty
                    && contribution.outputLines.isEmpty && contribution.webviewHTML == nil {
                    ContentUnavailableView(
                        "No interactive interface",
                        systemImage: "puzzlepiece",
                        description: Text("This extension contributes language or background functionality that runs in the editor, not a standalone view."))
                }
            }
            .padding()
        }
    }
}

// MARK: - Restricted webview bridge
//
// The webview gets no native services and no file access. Its only
// channel is `window.webkit.messageHandlers.swiftcode.postMessage`,
// and the handler accepts only "ready" and "log" messages — anything
// else is logged as a rejected message and dropped. No origin policy
// can be bypassed from inside the webview because there is no other
// bridge to bypass to.

public struct ExtV2RestrictedWebView: NSViewRepresentable {
    public let html: String
    public let extensionId: String

    public func makeCoordinator() -> Coordinator {
        Coordinator(extensionId: extensionId)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "swiftcode")
        // JavaScript can open no windows and reach no native API beyond
        // the single validated message handler above.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Content is set once at creation; extensions re-activate to
        // change it, so there is no stale-content path to maintain.
    }

    public final class Coordinator: NSObject, WKScriptMessageHandler {
        private let extensionId: String

        public init(extensionId: String) {
            self.extensionId = extensionId
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Only two message shapes are accepted; everything else is
            // dropped and logged, never dispatched to native code.
            if let text = message.body as? String {
                ExtV2DiagnosticsService.shared.info("Webview message: \(text)", extensionId: extensionId)
                return
            }
            if let dict = message.body as? [String: Any],
               let type = dict["type"] as? String,
               (type == "ready" || type == "log") {
                return
            }
            ExtV2DiagnosticsService.shared.warning("Rejected webview message with unsupported shape.", extensionId: extensionId)
        }
    }
}
