import Foundation

public enum PreviewUpdate: Equatable, Sendable {
    case none
    case relayout
    case reloadPayload
    case relaunchHost(reason: String)
    case rebuild(reason: String)
}

public struct PreviewInputs: Equatable, Sendable {
    public var destination: String
    public var module: String
    public var linked: Bool
    public var sourceHashes: [String: Int]
    public var resourceHashes: [String: Int]
    public var previewsHash: Int
    public var layout: [PreviewRegion]

    public init(destination: String, module: String, linked: Bool = false, sourceHashes: [String: Int],
                resourceHashes: [String: Int] = [:], previewsHash: Int, layout: [PreviewRegion]) {
        self.destination = destination
        self.module = module
        self.linked = linked
        self.sourceHashes = sourceHashes
        self.resourceHashes = resourceHashes
        self.previewsHash = previewsHash
        self.layout = layout
    }

    public static func hash(_ text: String) -> Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return Int(truncatingIfNeeded: h)
    }

    public static func hash(_ previews: [PreviewDeclaration]) -> Int {
        hash(previews.map { p -> String in
            let k: String = switch p.kind { case .macro(let b): "m:" + b; case .provider(let t): "p:" + t }
            return "\(p.name)|\(k)|\(p.traits.joined(separator: ","))|\(p.fixedSize.map { "\($0.width)x\($0.height)" } ?? "")"
        }.joined(separator: "\u{1}"))
    }
}

public struct PreviewHostState: Equatable, Sendable {
    public var running: Bool
    public var loads: Int
    public var failed: Bool
    public init(running: Bool, loads: Int = 0, failed: Bool = false) {
        self.running = running
        self.loads = loads
        self.failed = failed
    }
}

public enum PreviewUpdatePlanner {
    public static let maximumLoads = 40

    public static func decide(previous: PreviewInputs?, current: PreviewInputs, host: PreviewHostState) -> PreviewUpdate {
        if current.linked {
            return .rebuild(reason: "the target is linked from its package, so its sources cannot be compiled into a payload")
        }
        guard let previous else {
            return host.running ? .reloadPayload : .relaunchHost(reason: "first preview")
        }
        if previous.destination != current.destination { return .relaunchHost(reason: "the preview device changed") }
        if previous.module != current.module { return host.running ? .reloadPayload : .relaunchHost(reason: "the host is not running") }
        if previous.resourceHashes != current.resourceHashes {
            return .rebuild(reason: "resources changed; the host bundle is rebuilt with them")
        }
        let sourcesChanged = previous.sourceHashes != current.sourceHashes || previous.previewsHash != current.previewsHash
        if !host.running || host.failed {
            return .relaunchHost(reason: host.failed ? "the host failed" : "the host is not running")
        }
        if sourcesChanged {
            return host.loads >= maximumLoads ? .relaunchHost(reason: "the host has loaded \(host.loads) payloads") : .reloadPayload
        }
        if previous.layout != current.layout { return .relayout }
        return .none
    }
}
