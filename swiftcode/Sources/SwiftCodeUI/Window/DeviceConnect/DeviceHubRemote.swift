import AppKit
import SwiftCodeDeviceModel
import SwiftCodeDeviceUI
import SwiftCodeDisplayStream
import SwiftCodeIDECore

@MainActor
public final class RemoteDisplayLink {
    public let session: DeviceLiveSession
    public let localSocket: String
    private let remote: RemoteSimulator?
    private var forward: Process?
    private var watchdog: Timer?
    private static var counter = 0

    public init(remote: RemoteSimulator, name: String, os: String) {
        Self.counter += 1
        localSocket = (NSTemporaryDirectory() as NSString).appendingPathComponent("swiftcode-hub-\(getpid())-\(Self.counter).sock")
        self.remote = remote
        let hello = DisplayClientHello(client: "SwiftCode Device Hub", maxFPS: 60, encoding: "jpeg", quality: 80, downscale: 1)
        session = DeviceLiveSession(connection: ViewerConnection(address: .unix(localSocket), settings: hello), spec: remote.frameSpec)
        session.displayName = name
        session.osTitle = os
        startForward()
        session.start()
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.forward?.isRunning == false { self?.startForward() } }
        }
    }

    public init(address: DisplayAddress, spec: DeviceFrameSpec, name: String, os: String) {
        localSocket = ""
        remote = nil
        session = DeviceLiveSession(connection: ViewerConnection(address: address, settings: DisplayClientHello(client: "SwiftCode Device Hub")),
                                    spec: spec)
        session.displayName = name
        session.osTitle = os
        session.start()
    }

    private func startForward() {
        guard let remote else { return }
        unlink(localSocket)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: remote.settings.ssh)
        p.arguments = remote.displayForwardArguments(localSocket: localSocket)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run(); forward = p } catch { forward = nil }
    }

    public func close() {
        watchdog?.invalidate()
        session.close()
        if let f = forward, f.isRunning { f.terminate() }
        forward = nil
        if !localSocket.isEmpty { unlink(localSocket) }
    }
}

@MainActor
enum DeviceHubLaunch {
    private static var done = false

    static func openIfAsked(_ wc: WorkspaceWindowController) {
        let d = UserDefaults.standard
        guard !done, d.bool(forKey: "SwiftCodeOpenDeviceHub") else { return }
        done = true
        Task { @MainActor [weak wc] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let wc else { return }
            let c = await wc.presentDevices()
            if let q = d.string(forKey: "SwiftCodeDeviceHubSearch") { c.setSearch(q) }
            if let name = d.string(forKey: "SwiftCodeDeviceHubSelect"), let i = c.rows.firstIndex(where: { $0.name == name }) { c.select(row: i) }
            switch d.string(forKey: "SwiftCodeDeviceHubTab") {
            case "reports": c.selectInspectorTab(.reports)
            case "info": c.selectInspectorTab(.info)
            case "settings": c.selectInspectorTab(.settings)
            default: break
            }
            if d.bool(forKey: "SwiftCodeDeviceHubStart"), let r = c.selected { await c.start(r)?.value }
            if d.bool(forKey: "SwiftCodeDeviceHubCompact") {
                for _ in 0..<600 {
                    if let r = c.selected, r.state == "Booted", c.links[r.identifier]?.session.isLive == true { c.openInNewWindow(r); break }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
}
