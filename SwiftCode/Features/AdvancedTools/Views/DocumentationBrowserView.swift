import SwiftUI
import WebKit
import AppKit

struct DocumentationBrowserView: View {
    @State private var query = ""
    @State private var currentURL: URL? = URL(string: "https://developer.apple.com/documentation/swiftui")
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

    let frameworks = [
        "SwiftUI", "UIKit", "Combine", "CoreML", "AVFoundation", "CloudKit", "Metal"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Loading Indicator
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading Apple Developer Documentation…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.05))
                }

                // Framework Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(frameworks, id: \.self) { framework in
                            Button(action: {
                                loadFramework(framework)
                            }) {
                                Text(framework)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16) // Search section padding: 16 (shared)
                    .padding(.vertical, 12)
                }
                #if canImport(UIKit)
                .background(Color(uiColor: .secondarySystemBackground))
                #else
                .background(Color(nsColor: .windowBackgroundColor))
                #endif

                // Documentation Content
                if let currentURL {
                    DocsWebView(
                        url: currentURL,
                        isLoading: $isLoading,
                        canGoBack: $canGoBack,
                        canGoForward: $canGoForward,
                        reloadTrigger: $reloadTrigger,
                        backTrigger: $backTrigger,
                        forwardTrigger: $forwardTrigger,
                        extractedContent: $extractedContent
                    )
                    .padding(12)
                } else {
                    ContentUnavailableView(
                        "No URL Loaded",
                        systemImage: "book.closed",
                        description: Text("Search for documentation or select a framework shortcut to begin.")
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .navigationTitle("Documentation")
            .searchable(text: $query, prompt: "Search")
            .onSubmit(of: .search) {
                performSearch()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(action: {
                            guard EntitlementManager.shared.proAccess else {
                                showingPaywall = true
                                return
                            }
                            if let url = currentURL {
                                Task {
                                    await DocumentationAnalyzer.shared.analyze(url: url, documentationContent: extractedContent)
                                }
                                showingAIInsights = true
                            }
                        }) {
                            Label("AI Insights", systemImage: "apple.intelligence")
                        }

                        Button(action: { reloadTrigger.toggle() }) {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }

                        Button(action: openInSafari) {
                            Label("Open In Safari", systemImage: "safari")
                        }

                        Divider()

                        Button(action: { backTrigger.toggle() }) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(!canGoBack)

                        Button(action: { forwardTrigger.toggle() }) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(!canGoForward)

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
        }
    }

    private func openInSafari() {
        if let currentURL {
            #if canImport(AppKit)
            NSWorkspace.shared.open(currentURL)
            #endif
        }
    }

    private func loadFramework(_ name: String) {
        query = name
        performSearch()
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            currentURL = nil
            return
        }

        if trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: trimmed),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            currentURL = url
            return
        }

        let safePath = trimmed
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        currentURL = URL(string: "https://developer.apple.com/documentation/\(safePath)")
    }
}

private struct DocsWebView: PlatformViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    @Binding var reloadTrigger: Bool
    @Binding var backTrigger: Bool
    @Binding var forwardTrigger: Bool
    @Binding var extractedContent: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makePlatformView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Important: Apple documentation site uses dynamic rendering
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        loadIfValid(on: webView, url: url)
        return webView
    }

    func updatePlatformView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            loadIfValid(on: webView, url: url)
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

    private func loadIfValid(on webView: WKWebView, url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        webView.load(URLRequest(url: url))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: DocsWebView
        var lastReloadTrigger = false
        var lastBackTrigger = false
        var lastForwardTrigger = false

        init(_ parent: DocsWebView) {
            self.parent = parent
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

            // Extract content for AI Analysis
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

private typealias PlatformViewRepresentable = NSViewRepresentable

private extension DocsWebView {
    func makeNSView(context: Context) -> WKWebView {
        makePlatformView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updatePlatformView(webView, context: context)
    }
}
