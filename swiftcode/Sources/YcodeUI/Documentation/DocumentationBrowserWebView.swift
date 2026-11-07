import AppKit
import SwiftUI
import YcodeMCP
import WebKit

final class DocumentationURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private var stoppedTasks = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "docc" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let docPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        Task { [weak self, weak urlSchemeTask] in
            guard let self, let urlSchemeTask else { return }
            let html = await DocumentationCache.shared.renderedHTML(docPath: docPath)
            guard let data = html.data(using: .utf8) else {
                urlSchemeTask.didFailWithError(URLError(.cannotDecodeContentData))
                return
            }
            let stopped = self.lock.withLock { self.stoppedTasks.contains(ObjectIdentifier(urlSchemeTask)) }
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

struct DocumentationWebView: NSViewRepresentable {
    var docPath: String
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
                lastLoaded = url
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                onNavigate?(path)
                decisionHandler(.allow)
            case "http", "https":
                if url.host == "developer.apple.com" {
                    let docc = URL(string: "docc://developer.apple.com\(url.path)")!
                    lastLoaded = docc
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: docc))
                    onNavigate?(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                } else {
                    decisionHandler(.cancel)
                    NSWorkspace.shared.open(url)
                }
            default:
                decisionHandler(.cancel)
            }
        }
    }
}
