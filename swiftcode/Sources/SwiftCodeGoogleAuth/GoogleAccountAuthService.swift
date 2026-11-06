// NOTE (R-GOOGLE-MOVE, W-V2 decision 1, 2026-11-06): GoogleAccountAuthService and its
// ASWebAuthenticationPresentationContextProviding extension moved to SwiftCodeAssistant;
// only OAuthLoopbackServer remains in this file.

import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

import SwiftCodeAssistant
import CryptoKit
import Network
import Security
import os

// Ported from Legacy `SwiftCode/Services/GoogleAccountAuthService.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: OAuthLoopbackServer.

@MainActor
public final class OAuthLoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 8085
    public var onCallback: ((URL) -> Void)?

    public init() {}

    public func start() -> UInt16 {
        var candidatePorts: [UInt16] = [65000]
        candidatePorts.append(contentsOf: (UInt16(8085)...UInt16(8099)))
        for candidatePort in candidatePorts {
            do {
                let params = NWParameters.tcp
                guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { continue }
                let listener = try NWListener(using: params, on: nwPort)

                self.port = candidatePort
                self.listener = listener

                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.handleConnection(connection)
                    }
                }

                listener.start(queue: .main)
                return candidatePort
            } catch {
                continue
            }
        }

        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener.start(queue: .main)
            if let assignedPort = listener.port?.rawValue {
                self.port = assignedPort
                return assignedPort
            }
        } catch {
            logger.error("Failed to start OAuth loopback listener: \(error.localizedDescription)")
        }
        return 8085
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let requestString = String(data: data, encoding: .utf8) else {
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

            let html = """
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
}
