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

                // Header Search & Platform bar
                HStack(spacing: 12) {
                    TextField("Search documentation or enter URL...", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }

                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Divider().frame(height: 20)

                    // Back & Forward Controls
                    HStack(spacing: 4) {
                        Button {
                            backTrigger.toggle()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canGoBack)

                        Button {
                            forwardTrigger.toggle()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canGoForward)

                        Button {
                            reloadTrigger.toggle()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Framework Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(frameworks, id: \.self) { framework in
                            Button(action: {
                                loadFramework(framework)
                            }) {
                                Text(framework)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(query == framework ? Color.orange.opacity(0.2) : Color.accentColor.opacity(0.1))
                                    .clipShape(Capsule())
                                    .foregroundColor(query == framework ? .orange : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private func openInSafari() {
        if let currentURL {
            NSWorkspace.shared.open(currentURL)
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
