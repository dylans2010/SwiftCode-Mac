import Foundation

public enum SettingsChannel {
    public static let guestPaths = ["/private/var/run/dev.swiftcode.settings", "/var/run/dev.swiftcode.settings"]
    public static let protocolVersion = 1
    public static let maximumFrame = 1 << 20

    public static func frame(_ message: [String: Any]) -> [UInt8]? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0),
              data.count <= maximumFrame else { return nil }
        let n = UInt32(data.count)
        return [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + [UInt8](data)
    }

    public static func takeFrames(_ buffer: inout [UInt8]) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        while buffer.count >= 4 {
            let n = Int(buffer[0]) << 24 | Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
            guard n <= maximumFrame else { throw ChannelError.frameTooLarge(n) }
            guard buffer.count >= 4 + n else { break }
            let body = Data(buffer[4..<(4 + n)])
            buffer.removeFirst(4 + n)
            guard let o = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any] else {
                throw ChannelError.notADictionary
            }
            out.append(o)
        }
        return out
    }

    public enum ChannelError: Error, Equatable {
        case frameTooLarge(Int)
        case notADictionary
    }

    public static func apply(_ plan: SettingsPlan) -> [String: Any] {
        var m: [String: Any] = ["op": "apply",
                                "writes": plan.writes.map { w -> [String: Any] in
                                    var d: [String: Any] = ["domain": w.domain, "key": w.key]
                                    if let v = w.value { d["value"] = v.plistObject }
                                    return d
                                },
                                "notify": plan.notifications]
        if let w = plan.waitForVoiceOver { m["waitVoiceOver"] = w }
        if !plan.startServices.isEmpty { m["startServices"] = plan.startServices }
        return m
    }

    public static func read(_ reads: [PreferenceRead]) -> [String: Any] {
        ["op": "read", "reads": reads.map { ["domain": $0.domain, "key": $0.key] }]
    }

    public static func notify(_ names: [String]) -> [String: Any] { ["op": "notify", "notify": names] }
    public static func watch(_ names: [String]) -> [String: Any] { ["op": "watch", "notify": names] }

    public static func location(_ steps: [LocationStep]) -> [String: Any] {
        ["op": "location", "steps": steps.map(\.dictionary)]
    }

    public static func values(of reply: [String: Any]) -> [String: PrefValue] {
        var out: [String: PrefValue] = [:]
        for (k, v) in reply["values"] as? [String: Any] ?? [:] {
            if let p = PrefValue(plistObject: v) { out[k] = p }
        }
        return out
    }
}
