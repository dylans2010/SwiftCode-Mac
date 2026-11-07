import Foundation

public enum SimRemoteCLI {
    static func out(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
    static func err(_ s: String) { FileHandle.standardError.write(Data(("swiftcode sim remote: " + s + "\n").utf8)) }

    public static let usage = """
        usage: swiftcode sim remote pair <host>[:port] <code> [--name N] [--media-port P]
               swiftcode sim remote identity [--name N] | trust <file.json> [--address host:port] | hosts | unpair <name>
               swiftcode sim remote [--host N] info | devices | log <device> [lines] | create <device> --type T
               swiftcode sim remote [--host N] boot <device> [--cold] | shutdown <device>
               swiftcode sim remote [--host N] install <App.app> | run <device> <App.app> [--bundle-id ID] [--no-view]
               swiftcode sim remote [--host N] view <device> [--xr] [viewer options]
               swiftcode sim remote [--host N] view <device> --xr --background [viewer options] | --desktop [--no-window]
        """

    public static func viewerPath() -> String {
        if let v = ProcessInfo.processInfo.environment["SWIFTCODE_SIM_VIEWER"], !v.isEmpty { return v }
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let next = me.deletingLastPathComponent().appendingPathComponent("swiftcode-sim-viewer").path
        return FileManager.default.isExecutableFile(atPath: next) ? next : "swiftcode-sim-viewer"
    }

    public static func xrViewerPath() -> String {
        if let v = ProcessInfo.processInfo.environment["SWIFTCODE_XR_VIEWER"], !v.isEmpty { return v }
        let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let next = me.deletingLastPathComponent().appendingPathComponent("swiftcode-xr-viewer").path
        return FileManager.default.isExecutableFile(atPath: next) ? next : "swiftcode-xr-viewer"
    }

    public static func viewerArguments(host: String?, device: String, extra: [String]) -> [String] {
        ["--link", device] + (host.map { ["--host", $0] } ?? []) + extra
    }

    public static func main(_ arguments: [String]) -> Int32 {
        var a = arguments
        func take(_ name: String) -> String? {
            guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
            let v = a[i + 1]
            a.removeSubrange(i...(i + 1))
            return v
        }
        func flag(_ name: String) -> Bool {
            guard let i = a.firstIndex(of: name) else { return false }
            a.remove(at: i)
            return true
        }
        let hostName = take("--host")
        guard !a.isEmpty else { err(usage); return 64 }
        let cmd = a.removeFirst()
        let store = LinkStore()
        do {
            let client = try LinkClient(store: store)
            switch cmd {
            case "pair":
                let name = take("--name"), mport = take("--media-port").flatMap(Int.init)
                guard a.count == 2 else { err(usage); return 64 }
                let (h, p) = SimHostConfig.splitHostPort(a[0], defaultPort: LinkDefaults.controlPort)
                let peer = try client.pair(host: h, port: p, code: a[1], name: name ?? h, mediaPort: mport)
                out("paired with \(peer.name) (\(h):\(p)); its identity is \(peer.keyBytes.map(LinkIdentity.fingerprint) ?? "?")")
            case "identity":
                let f = PairingFile(name: take("--name") ?? ProcessInfo.processInfo.hostName, identity: client.identity, role: "client")
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                out(String(decoding: try enc.encode(f), as: UTF8.self))
                err("fingerprint \(client.identity.fingerprint)")
            case "trust":
                let address = take("--address")
                guard let path = a.first, let d = FileManager.default.contents(atPath: path),
                      let f = try? JSONDecoder().decode(PairingFile.self, from: d), let key = Data(base64Encoded: f.publicKey), key.count == 32,
                      let addr = address ?? f.address else {
                    err("trust <pairing file from `swiftcode-simhost identity`> [--address host:port]"); return 64
                }
                try store.addPeer(TrustedPeer(name: f.name, publicKey: Array(key), role: "host", address: addr, mediaPort: f.mediaPort))
                out("trusted host \(f.name) at \(addr) (\(LinkIdentity.fingerprint(Array(key))))")
            case "hosts":
                for p in store.peers() where p.role == "host" {
                    out("\(p.name)\t\(p.address ?? "?")\t\(p.keyBytes.map(LinkIdentity.fingerprint) ?? "?")")
                }
            case "unpair":
                guard let n = a.first else { err(usage); return 64 }
                out(try store.removePeer(named: n) ? "removed \(n)" : "no host \(n)")
            case "info", "devices", "log", "create", "boot", "shutdown":
                let h = try client.host(named: hostName)
                let c = try client.control(h)
                defer { c.close() }
                var req = LinkRequest(op: cmd, device: a.first)
                if cmd == "log" { req.lines = a.count > 1 ? Int(a[1]) : 80 }
                if cmd == "create" { req.deviceType = take("--type") }
                if cmd == "boot" { req.cold = flag("--cold") }
                let r = try c.request(req)
                guard r.ok else { err(r.error ?? "failed"); return 1 }
                if let m = r.message { out(m) }
                if let host = r.host { out("host \(host) (\(LinkIdentity.fingerprint(h.publicKey)))") }
                if let t = r.deviceTypes { out("device types: " + t.joined(separator: " ")) }
                if let rt = r.runtimes { for x in rt { out("runtime \(x)") } }
                for d in r.devices ?? [] { out("\(d.name)\t\(d.deviceType)\t\(d.state)\t\(URL(fileURLWithPath: d.runtime).deletingLastPathComponent().lastPathComponent)" + (d.app.map { "\t\($0)" } ?? "")) }
                for l in r.log ?? [] { out(l) }
            case "install", "run":
                let bundle = take("--bundle-id"), noView = flag("--no-view")
                let device: String?
                let appPath: String
                if cmd == "install" {
                    guard a.count == 1 else { err(usage); return 64 }
                    (device, appPath) = (nil, a[0])
                } else {
                    guard a.count >= 2 else { err(usage); return 64 }
                    (device, appPath) = (a[0], a[1])
                }
                let app = URL(fileURLWithPath: appPath).standardizedFileURL
                let h = try client.host(named: hostName)
                let c = try client.control(h)
                defer { c.close() }
                let started = Date()
                let up = try c.upload(app)
                guard up.ok else { err(up.error ?? "upload failed"); return 1 }
                out("uploaded \(up.message ?? app.lastPathComponent) (round trip \(String(format: "%.2f", Date().timeIntervalSince(started))) s)")
                guard let device else { return 0 }
                let r = try c.request(LinkRequest(op: "run", device: device, app: app.lastPathComponent, bundleID: bundle ?? up.bundleID))
                guard r.ok else { err(r.error ?? "run failed"); return 1 }
                out("\(device): installing and launching \(r.bundleID ?? "?")")
                if noView { return 0 }
                return exec(viewerPath(), viewerArguments(host: hostName, device: device, extra: Array(a.dropFirst(2))))
            case "view":
                let xr = flag("--xr")
                guard let device = a.first else { err(usage); return 64 }
                return exec(xr ? xrViewerPath() : viewerPath(), viewerArguments(host: hostName, device: device, extra: Array(a.dropFirst())))
            default:
                err(usage)
                return 64
            }
        } catch {
            err("\(error)")
            return 1
        }
        return 0
    }

    static func exec(_ path: String, _ args: [String]) -> Int32 {
        let argv = ([path] + args).map { strdup($0) } + [nil]
        execvp(path, argv)
        err("cannot run \(path): \(String(cString: strerror(errno)))")
        return 127
    }
}
