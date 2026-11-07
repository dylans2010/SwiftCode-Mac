import Foundation

extension DeviceLayout {
    static let memoryFilesEnabled: Bool = ProcessInfo.processInfo.environment["SWIFTCODE_FRAME_RECORD_MEMORY"] != "0"

    var memoryGuestPath: String { guestDev + "/swiftcode-memory" }

    static var memoryBase: String? {
        guard memoryFilesEnabled else { return nil }
        let base = getenv("SWIFTCODE_MEMORY_DIR").map { String(cString: $0) }.flatMap { $0.isEmpty ? nil : $0 } ?? "/dev/shm"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base, isDirectory: &isDirectory), isDirectory.boolValue,
              access(base, W_OK) == 0 else { return nil }
        return base
    }

    static var memoryNamePrefix: String { "swiftcode-\(getuid())-" }

    var memoryHostPath: String {
        guard let base = Self.memoryBase else { return data + "/tmp/swiftcode-memory" }
        return base + "/" + Self.memoryNamePrefix + Self.stableUDID(for: dev).replacingOccurrences(of: "-", with: "").prefix(16)
    }

    static let memoryOwnerName = ".owner"

    static func sweepStaleMemoryDirectories(except keep: String) {
        guard let base = memoryBase else { return }
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: base)) ?? [] where name.hasPrefix(memoryNamePrefix) {
            let dir = base + "/" + name
            guard dir != keep else { continue }
            if let text = fm.contents(atPath: dir + "/" + memoryOwnerName).map({ String(decoding: $0, as: UTF8.self) }),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if kill(pid, 0) == 0 || errno == EPERM { continue }
            } else {
                let made = (try? fm.attributesOfItem(atPath: dir)[.modificationDate] as? Date) ?? Date()
                guard Date().timeIntervalSince(made) > 86_400 else { continue }
            }
            try? fm.removeItem(atPath: dir)
        }
    }

    var memorySavedPath: String { dev + "/swiftcode-memory.saved" }

    func memoryFile(_ name: String) -> (host: String, guest: String) {
        (memoryHostPath + "/" + name, memoryGuestPath + "/" + name)
    }

    static let memoryTimingNames = ["swiftcode-framebuffer.timing", "swiftcode-simhid.timing", "swiftcode-display.trace"]

    func prepareMemoryDirectory() throws {
        let fm = FileManager.default
        let host = memoryHostPath
        Self.sweepStaleMemoryDirectories(except: host)
        try fm.createDirectory(atPath: host, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in (try? fm.contentsOfDirectory(atPath: host)) ?? [] { try? fm.removeItem(atPath: host + "/" + name) }
        if host != data + "/tmp/swiftcode-memory" {
            try? Data("\(getpid())\n".utf8).write(to: URL(fileURLWithPath: host + "/" + Self.memoryOwnerName))
            for name in Self.memoryTimingNames {
                let link = data + "/tmp/" + name
                try? fm.removeItem(atPath: link)
                if Self.displayTiming { try? fm.createSymbolicLink(atPath: link, withDestinationPath: host + "/" + name) }
            }
        }
        guard restoring else { return }
        for name in (try? fm.contentsOfDirectory(atPath: memorySavedPath)) ?? [] where name != Self.memoryOwnerName {
            try Self.copyKeepingTime(memorySavedPath + "/" + name, host + "/" + name)
        }
    }

    func saveMemoryDirectory() {
        let fm = FileManager.default
        let saved = memorySavedPath, partial = saved + ".partial"
        try? fm.removeItem(atPath: partial)
        do {
            try fm.createDirectory(atPath: partial, withIntermediateDirectories: true)
            for name in try fm.contentsOfDirectory(atPath: memoryHostPath) where name != Self.memoryOwnerName {
                try Self.copyKeepingTime(memoryHostPath + "/" + name, partial + "/" + name)
            }
            try? fm.removeItem(atPath: saved)
            try fm.moveItem(atPath: partial, toPath: saved)
        } catch {
            FileHandle.standardError.write(Data("swiftcode-simd: warning: cannot save the memory directory: \(error)\n".utf8))
        }
    }

    func finishMemoryDirectory() {
        let fm = FileManager.default
        let host = memoryHostPath
        guard host != data + "/tmp/swiftcode-memory" else { return }
        for name in Self.memoryTimingNames where fm.fileExists(atPath: host + "/" + name) {
            try? fm.removeItem(atPath: data + "/tmp/" + name)
            try? fm.copyItem(atPath: host + "/" + name, toPath: data + "/tmp/" + name)
        }
        try? fm.removeItem(atPath: host)
    }

    static func copyKeepingTime(_ from: String, _ to: String) throws {
        let fm = FileManager.default
        try fm.copyItem(atPath: from, toPath: to)
        if let date = try fm.attributesOfItem(atPath: from)[.modificationDate] as? Date {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: to)
        }
    }
}
