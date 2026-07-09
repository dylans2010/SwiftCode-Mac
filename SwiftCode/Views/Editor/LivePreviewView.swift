import SwiftUI
import WebKit

struct LivePreviewView: View {
    let url: URL

    var body: some View {
        WebView(url: url)
            .background(Color.white)
    }
}

struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        nsView.load(request)
    }
}
