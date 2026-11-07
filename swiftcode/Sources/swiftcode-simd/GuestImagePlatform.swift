import Foundation

enum GuestImagePlatform {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func packedVersion(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".").map { UInt32($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let p = parts.map { $0! } + Array(repeating: 0, count: 3 - parts.count)
        guard p[0] <= 0xFFFF, p[1] <= 0xFF, p[2] <= 0xFF else { return nil }
        return p[0] << 16 | p[1] << 8 | p[2]
    }

    static func retagged(_ image: Data, platform: UInt32, minOS: UInt32, sdk: UInt32) throws -> Data {
        var bytes = [UInt8](image)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        func put(_ v: UInt32, _ at: Int) { for i in 0..<4 { bytes[at + i] = UInt8(truncatingIfNeeded: v >> (8 * i)) } }
        guard bytes.count >= 32, u32(0) == 0xFEED_FACF else { throw Failure(description: "not a thin 64-bit Mach-O image") }
        let ncmds = Int(u32(16)), sizeofcmds = Int(u32(20))
        guard 32 + sizeofcmds <= bytes.count else { throw Failure(description: "load commands run past the end") }
        var at = 32, found: Int?
        for _ in 0..<ncmds {
            guard at + 8 <= 32 + sizeofcmds else { throw Failure(description: "truncated load command") }
            let cmd = u32(at), size = Int(u32(at + 4))
            guard size >= 8, at + size <= 32 + sizeofcmds else { throw Failure(description: "bad load command size") }
            if cmd == 0x1D { throw Failure(description: "the image is signed; its signature would no longer match") }
            if cmd == 0x32 {
                guard found == nil else { throw Failure(description: "more than one LC_BUILD_VERSION") }
                guard size >= 24 else { throw Failure(description: "short LC_BUILD_VERSION") }
                found = at
            }
            at += size
        }
        guard let command = found else { throw Failure(description: "no LC_BUILD_VERSION") }
        put(platform, command + 8)
        put(minOS, command + 12)
        put(sdk, command + 16)
        return Data(bytes)
    }

    static func platform(of image: Data) -> UInt32? {
        let b = [UInt8](image)
        func u32(_ at: Int) -> UInt32 {
            UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
        }
        guard b.count >= 32, u32(0) == 0xFEED_FACF else { return nil }
        var at = 32
        for _ in 0..<Int(u32(16)) {
            guard at + 12 <= b.count else { return nil }
            let size = Int(u32(at + 4))
            if u32(at) == 0x32 { return u32(at + 8) }
            guard size >= 8 else { return nil }
            at += size
        }
        return nil
    }

    static func adapt(fileAt path: String, for runtime: RuntimePlatform, version: String) throws {
        guard runtime != .iOS else { return }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw Failure(description: "cannot read \(path)")
        }
        let v = packedVersion(version) ?? 27 << 16
        let out = try retagged(data, platform: runtime.machOPlatform, minOS: v, sdk: v)
        if out != data { try out.write(to: URL(fileURLWithPath: path), options: .atomic) }
    }

    static func adaptedCopy(of source: String, to target: String, for runtime: RuntimePlatform, version: String) throws -> String {
        guard let data = FileManager.default.contents(atPath: source) else {
            throw Failure(description: "cannot read \(source)")
        }
        let v = packedVersion(version) ?? 27 << 16
        let out = try retagged(data, platform: runtime.machOPlatform, minOS: v, sdk: v)
        let fm = FileManager.default
        if fm.contents(atPath: target) != out {
            try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try out.write(to: URL(fileURLWithPath: target), options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        }
        return target
    }
}
