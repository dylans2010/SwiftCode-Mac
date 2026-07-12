import SwiftUI
import WebKit
import AppKit

extension Notification.Name {
    static let loadDocURL = Notification.Name("com.swiftcode.loadDocURL")
}

struct DocumentationBrowserView: View {
    @State private var searchQuery = ""
    @State private var currentURL: URL? = URL(string: "https://developer.apple.com/documentation")
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var canGoForward = false

    // Actions to trigger WebView methods
    @State private var reloadTrigger = false
    @State private var backTrigger = false
    @State private var forwardTrigger = false
    @State private var showingAIInsights = false
    @State private var showingPaywall = false
    @State private var extractedContent: String?
    @State private var loadURLTrigger: URL? = nil

    let frameworks = [
        "SwiftUI", "Swift", "AppKit", "Foundation", "Combine", "CoreML", "Metal"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Dynamic Header Bar (Clean & Professional macOS Appearance)
                HStack(spacing: 16) {
                    // Back & Forward Controls
                    HStack(spacing: 6) {
                        Button {
                            backTrigger.toggle()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canGoBack)
                        .help("Go Back")

                        Button {
                            forwardTrigger.toggle()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canGoForward)
                        .help("Go Forward")

                        Button {
                            reloadTrigger.toggle()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .help("Reload")
                    }

                    // Native Search Integration
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search Apple Developer Documentation...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .onSubmit { performAppleSearch() }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    Button("Search") {
                        performAppleSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Framework Shortcuts (Beautiful Interactive Chips)
                HStack(spacing: 10) {
                    Text("Shortcut frameworks:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(frameworks, id: \.self) { framework in
                                Button(action: {
                                    loadFramework(framework)
                                }) {
                                    Text(framework)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Main Web Frame
                ZStack {
                    DocsWebView(
                        url: currentURL ?? URL(string: "https://developer.apple.com/documentation")!,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        reloadTrigger: $reloadTrigger,
                        backTrigger: $backTrigger,
                        forwardTrigger: $forwardTrigger,
                        extractedContent: $extractedContent,
                        loadURLTrigger: $loadURLTrigger
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Apple Developer Documentation")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            guard EntitlementManager.shared.proAccess else {
                                showingPaywall = true
                                return
                            }
                            if let url = loadURLTrigger ?? currentURL {
                                Task {
                                    await DocumentationAnalyzer.shared.analyze(url: url, documentationContent: extractedContent)
                                }
                                showingAIInsights = true
                            }
                        }) {
                            Label("AI Insights", systemImage: "apple.intelligence")
                        }

                        Button(action: openInSafari) {
                            Label("Open In Safari", systemImage: "safari")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAIInsights) {
                DocumentationAIInsightsView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .loadDocURL)) { notification in
                if let url = notification.userInfo?["url"] as? URL {
                    loadURLTrigger = url
                    currentURL = url
                }
            }
        }
    }

    private func openInSafari() {
        if let url = loadURLTrigger ?? currentURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadFramework(_ name: String) {
        searchQuery = name
        let path = name.lowercased()
        if let url = URL(string: "https://developer.apple.com/documentation/\(path)") {
            loadURLTrigger = url
        }
    }

    private func performAppleSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://developer.apple.com/search/?q=\(encoded)") {
            loadURLTrigger = url
        }
    }
}

private struct DocsWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    @Binding var reloadTrigger: Bool
    @Binding var backTrigger: Bool
    @Binding var forwardTrigger: Bool
    @Binding var extractedContent: String?
    @Binding var loadURLTrigger: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let targetURL = loadURLTrigger {
            loadURLTrigger = nil
            webView.load(URLRequest(url: targetURL))
        }

        if reloadTrigger != context.coordinator.lastReloadTrigger {
            webView.reload()
            context.coordinator.lastReloadTrigger = reloadTrigger
        }

        if backTrigger != context.coordinator.lastBackTrigger {
            if webView.canGoBack { webView.goBack() }
            context.coordinator.lastBackTrigger = backTrigger
        }

        if forwardTrigger != context.coordinator.lastForwardTrigger {
            if webView.canGoForward { webView.goForward() }
            context.coordinator.lastForwardTrigger = forwardTrigger
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: DocsWebView
        var lastReloadTrigger = false
        var lastBackTrigger = false
        var lastForwardTrigger = false

        init(_ parent: DocsWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let host = url.host?.lowercased() ?? ""
                // Exclusively restrict navigation to Apple sites to safeguard the user context
                if host.contains("apple.com") {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                }
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }

            webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
                guard let content = result as? String, error == nil else { return }
                DispatchQueue.main.async {
                    self?.parent.extractedContent = content
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}
