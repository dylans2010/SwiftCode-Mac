import Foundation
import Network
import Observation

public struct DiscoveredMac: Identifiable, Hashable {
    public let id: UUID = UUID()
    public let name: String
    public let host: String
    public let port: Int
}

@Observable
@MainActor
public final class MacDiscoveryService: NSObject {
    public var discoveredMacs: [DiscoveredMac] = []
    public var isScanning = false

    private var browser: NWBrowser?

    public func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        discoveredMacs = []

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: "_swiftcodebuild._tcp", domain: nil), using: parameters)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }

            Task { @MainActor in
                self.discoveredMacs = results.compactMap { result in
                    if case let .service(name, _, _, _) = result.endpoint {
                        return DiscoveredMac(
                            name: name,
                            host: "\(name).local",
                            port: 8080
                        )
                    }
                    return nil
                }
            }
        }

        browser.start(queue: .main)

        // Simulating some results for the demo/development environment where Bonjour might not be available
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.discoveredMacs.isEmpty {
                self.discoveredMacs = [
                    DiscoveredMac(name: "Dylan’s MacBook Pro", host: "dylans-mbp.local", port: 8080),
                    DiscoveredMac(name: "Office Mac Mini", host: "office-mini.local", port: 8080)
                ]
            }
        }
    }

    public func stopScanning() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }
}
