import Foundation

#if canImport(Network)
import Network
#endif

/// The local loopback HTTP listener the browser flow redirects to
/// (RFC 8252, Google's OAuth 2.0 policy for desktop apps).
///
/// Ported from Legacy's `OAuthLoopbackServer`: it binds the first
/// free port in `GoogleOAuthConfiguration.preferredLoopbackPorts`
/// (65000, then 8085...8099), falling back to an ephemeral port,
/// serves one success page per connection, and hands the full
/// redirect URL (path + query) to `onCallback`.
///
/// The success page is the same page Legacy served (dark card,
/// "Authentication Successful", a redirect to the
/// `swiftcode://oauth-callback` scheme after 350 ms and a window
/// close after 2 seconds), with the product name kept as SwiftCode
/// to match the Accounts pane's "SwiftCode Account" naming.
///
/// On platforms without the `Network` framework (Linux) the
/// listener cannot exist: `start()` returns nil and the sign-in
/// flow fails honestly with `.loopbackUnavailable` instead of
/// pretending a browser flow ran.
public final class GoogleLoopbackServer: @unchecked Sendable {
    /// The port the listener bound, once started.
    public private(set) var port: UInt16 = 0
    /// Called with the full redirect URL for each request line
    /// received (host prefix + path + query).
    public var onCallback: ((URL) -> Void)?

    public init() {}

    /// Binds the first free preferred port (or an ephemeral one)
    /// and starts listening. Returns the bound port, or nil when no
    /// listener could be started.
    public func start() -> UInt16? {
        #if canImport(Network)
        for candidatePort in GoogleOAuthConfiguration.preferredLoopbackPorts {
            if let bound = tryBind(port: candidatePort) { return bound }
        }
        if let bound = tryBind(port: nil) { return bound }
        return nil
        #else
        return nil
        #endif
    }

    /// Stops listening.
    public func stop() {
        #if canImport(Network)
        listener?.cancel()
        listener = nil
        #endif
    }

    #if canImport(Network)
    private var listener: NWListener?

    private func tryBind(port candidatePort: UInt16?) -> UInt16? {
        do {
            let params = NWParameters.tcp
            let endpointPort: NWEndpoint.Port
            if let candidatePort {
                guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { return nil }
                endpointPort = nwPort
            } else {
                endpointPort = .any
            }
            let listener = try NWListener(using: params, on: endpointPort)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener.start(queue: .main)
            if let assigned = listener.port?.rawValue {
                self.port = assigned
                return assigned
            }
            if let candidatePort {
                self.port = candidatePort
                return candidatePort
            }
            return nil
        } catch {
            return nil
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let lines = requestString.components(separatedBy: "\r\n")
            if let firstLine = lines.first {
                let parts = firstLine.components(separatedBy: " ")
                if parts.count >= 2 {
                    let pathAndQuery = parts[1]
                    let hostPrefix = (self.port == 65000) ? "http://localhost:65000" : "http://127.0.0.1:\(self.port)"
                    if let url = URL(string: "\(hostPrefix)\(pathAndQuery)") ?? URL(string: "http://127.0.0.1:\(self.port)\(pathAndQuery)") {
                        Task { @MainActor in
                            self.onCallback?(url)
                        }
                    }
                }
            }

            let html = GoogleLoopbackServer.successPage
            let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            if let responseData = httpResponse.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
        }
    }
    #endif

    /// The page served to the browser after a redirect arrives.
    /// Legacy's page verbatim (product name SwiftCode, matching the
    /// Accounts pane). Kept as a static string so tests can check
    /// the redirect target without starting a listener.
    public static let successPage = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>SwiftCode - Authentication Successful</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background-color: #0d1117; color: #c9d1d9; }
                .card { text-align: center; padding: 40px; border-radius: 16px; background: #161b22; border: 1px solid #30363d; box-shadow: 0 8px 24px rgba(0,0,0,0.5); max-width: 400px; }
                h2 { color: #58a6ff; margin-bottom: 12px; }
                p { color: #8b949e; line-height: 1.5; }
            </style>
        </head>
        <body>
            <div class="card">
                <h2>Authentication Successful</h2>
                <p>You have successfully authenticated with Google Antigravity.</p>
                <p>Returning to <strong>SwiftCode</strong>...</p>
            </div>
            <script>
                setTimeout(function() {
                    window.location.href = "swiftcode://oauth-callback";
                }, 350);
                setTimeout(function() {
                    window.close();
                }, 2000);
            </script>
        </body>
        </html>
        """

    /// Parses the first line of an HTTP request into the redirect
    /// URL the listener would hand to `onCallback`: the host prefix
    /// for `port` plus the request target (path + query). Pure, so
    /// tests can check loopback URL parsing without a socket.
    /// Returns nil when the request line has no target.
    public static func callbackURL(fromRequestLine line: String, port: UInt16) -> URL? {
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let pathAndQuery = parts[1]
        let hostPrefix = port == 65000 ? "http://localhost:65000" : "http://127.0.0.1:\(port)"
        return URL(string: "\(hostPrefix)\(pathAndQuery)") ?? URL(string: "http://127.0.0.1:\(port)\(pathAndQuery)")
    }
}
