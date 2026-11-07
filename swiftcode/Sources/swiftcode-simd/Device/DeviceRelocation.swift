import Foundation

extension DeviceLayout {
    var devicePathRecordPath: String { dev + "/swiftcode-device-path" }
    var launchServicesStorePath: String { data + "/var/db/lsd" }

    func launchServicesStoreFiles() -> [String] {
        Self.launchServicesStoreFiles(inData: data)
    }

    static func launchServicesStoreFiles(inData data: String) -> [String] {
        let dir = data + "/var/db/lsd"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.hasSuffix(".csstore") }.sorted().map { dir + "/" + $0 }
    }

    static func recordedGuestDevicePath(in device: String) -> String? {
        guard let bytes = FileManager.default.contents(atPath: device + "/swiftcode-device-path") else { return nil }
        let path = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func carriedGuestDevicePath(in device: String) -> String? {
        if let recorded = recordedGuestDevicePath(in: device) { return recorded }
        for file in launchServicesStoreFiles(inData: device + "/data") {
            guard let bytes = FileManager.default.contents(atPath: file) else { continue }
            if let path = foreignDevicePath(in: bytes, current: "") { return path }
        }
        return nil
    }

    func resolveGuestDevicePath() -> String {
        let fm = FileManager.default
        let carried: String?
        if !fm.fileExists(atPath: data), let templatePath {
            carried = Self.carriedGuestDevicePath(in: templatePath)
        } else {
            carried = Self.carriedGuestDevicePath(in: dev)
        }
        guard let carried, carried != dev else { return dev }
        if let problem = guestDevicePathProblem(carried) {
            FileHandle.standardError.write(Data("swiftcode-simd: device data carries the guest path \(carried), which \(problem); the device uses its own path\n".utf8))
            return dev
        }
        return carried
    }

    func guestDevicePathProblem(_ path: String) -> String? {
        guard path.hasPrefix("/"), path.count > 1, (path as NSString).standardizingPath == path, !path.hasSuffix("/") else {
            return "is not a normalized absolute path"
        }
        func overlaps(_ a: String, _ b: String) -> Bool { a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") }
        for shadowed in ["/tmp", "/var", "/etc", "/private", "/System", "/dev"] where overlaps(path, shadowed) {
            return "overlaps the guest's \(shadowed)"
        }
        if overlaps(path, runtimeRoot) { return "overlaps the runtime root" }
        for job in jobPaths where !(job == dev || job.hasPrefix(dev + "/")) && overlaps(path, job) {
            return "overlaps the job path \(job)"
        }
        return nil
    }

    static func foreignDevicePath(in bytes: Data, current: String) -> String? {
        let marker = Array("/data/Containers/".utf8)
        return bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
            guard let base = raw.baseAddress, raw.count >= marker.count else { return nil }
            let b = raw.bindMemory(to: UInt8.self)
            var offset = 0
            let last = raw.count - marker.count
            while offset <= last {
                guard let hit = memchr(base + offset, Int32(marker[0]), last - offset + 1) else { return nil }
                let i = base.distance(to: UnsafeRawPointer(hit))
                guard marker.withUnsafeBytes({ memcmp(base + i, $0.baseAddress!, marker.count) }) == 0 else {
                    offset = i + 1
                    continue
                }
                var start = i
                while start > 0, (0x20...0x7E).contains(b[start - 1]) { start -= 1 }
                if let slash = (start..<i).first(where: { b[$0] == UInt8(ascii: "/") }) {
                    let prefix = String(decoding: UnsafeBufferPointer(rebasing: b[slash..<i]), as: UTF8.self)
                    if prefix != current { return prefix }
                }
                offset = i + marker.count
            }
            return nil
        }
    }

    func handleRelocation() throws {
        let fm = FileManager.default
        if guestDev != dev {
            FileHandle.standardError.write(Data("swiftcode-simd: device data keeps its guest path \(guestDev) (copied or moved from there)\n".utf8))
        }
        var stale: [(file: String, names: String)] = []
        for file in launchServicesStoreFiles() {
            guard let bytes = fm.contents(atPath: file) else { continue }
            if let other = Self.foreignDevicePath(in: bytes, current: guestDev) { stale.append((file, other)) }
        }
        for entry in stale { try fm.removeItem(atPath: entry.file) }
        if let first = stale.first {
            FileHandle.standardError.write(Data(("swiftcode-simd: the LaunchServices store names \(first.names), not the device's guest path "
                + "\(guestDev): removed (\(stale.count) files), lsd rebuilds it at this boot\n").utf8))
        }
        if fm.fileExists(atPath: data) {
            try Data((guestDev + "\n").utf8).write(to: URL(fileURLWithPath: devicePathRecordPath), options: .atomic)
        }
    }
}
