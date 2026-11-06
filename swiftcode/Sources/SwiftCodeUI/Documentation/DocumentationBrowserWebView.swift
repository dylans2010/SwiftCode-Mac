import AppKit
import WebKit

// MARK: - Documentation web pane (Wave 19 slice A)
//
// The `docc://` scheme handler and the `WKWebView` wrapper for the
// Documentation Browser's web pane.
//
// Legacy's `DocCURLSchemeHandler` served files from the bundled
// `Documentation Assets` tree (Apple resources — dropped, not
// copied). This handler serves SwiftCode's own HTML renderer over
// the offline cache (`DocumentationCache.renderedHTML`) and
// nothing else: no archive files, no local file loading, no
// JavaScript. A path with no cached page renders the cache's own
// "not cached yet" / 404 page, never an invented document.
//
// Spec: `specs/ide/wave19-docs.md` §6.

/// Serves cached DocC pages for `docc://` URLs. The renderer only
/// ever emits `docc://developer.apple.com/documentation/…` URLs;
/// anything else gets a 404 page naming the path.
final class DocumentationURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private var stoppedTasks = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "docc" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // docc://developer.apple.com/documentation/swiftui/vstack
        // → docPath "documentation/swiftui/vstack".
        let docPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        Task { [weak self, weak urlSchemeTask] in
            guard let self, let urlSchemeTask else { return }
            let html = await DocumentationCache.shared.renderedHTML(docPath: docPath)
            guard let data = html.data(using: .utf8) else {
                urlSchemeTask.didFailWithError(URLError(.cannotDecodeContentData))
                return
            }
            self.lock.lock()
            let stopped = self.stoppedTasks.contains(ObjectIdentifier(urlSchemeTask))
            self.lock.unlock()
            guard !stopped else { return }
            let response = URLResponse(url: url, mimeType: "text/html",
                                       expectedContentLength: data.count, textEncodingName: "utf-8")
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask))
        lock.unlock()
    }
}

/// The Documentation Browser's web pane: a `WKWebView` showing the
/// cached DocC page for `docPath` ("" = the framework home page).
/// Link clicks stay in-app (`docc://`), developer.apple.com links
/// are rewritten to `docc://`, and every other http(s) link opens
/// in the user's browser.
struct DocumentationWebView: NSViewRepresentable {
    var docPath: String
    /// Called with the new DocC path (no leading slash) whenever
    /// the web pane navigates, so the workspace's selection,
    /// history, and sidebar stay in sync.
    var onNavigate: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DocumentationURLSchemeHandler(), forURLScheme: "docc")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let url = URL(string: "docc://developer.apple.com/\(docPath)")!
        guard context.coordinator.lastLoaded != url else { return }
        context.coordinator.lastLoaded = url
        view.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: ((String) -> Void)?
        var lastLoaded: URL?

        init(onNavigate: ((String) -> Void)?) {
            self.onNavigate = onNavigate
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            switch url.scheme {
            case "docc":
                // In-app navigation: the scheme handler serves it.
                // Record it so updateNSView does not reload the
                // same URL after onNavigate updates the selection.
                lastLoaded = url
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                onNavigate?(path)
                decisionHandler(.allow)
            case "http", "https":
                if url.host == "developer.apple.com" {
                    // Rewrite to the cached docc:// equivalent and
                    // load it in place.
                    let docc = URL(string: "docc://developer.apple.com\(url.path)")!
                    lastLoaded = docc
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: docc))
                    onNavigate?(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                } else {
                    // Anything else leaves the app.
                    decisionHandler(.cancel)
                    NSWorkspace.shared.open(url)
                }
            default:
                // No local file loading from the web pane.
                decisionHandler(.cancel)
            }
        }
    }
}
