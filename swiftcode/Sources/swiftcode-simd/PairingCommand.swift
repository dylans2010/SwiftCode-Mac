import Foundation
import SwiftCodeSimFeatures

enum PairingDeviceDirectory {
    static func udid(of dir: String) -> String {
        if let data = FileManager.default.contents(atPath: dir + "/" + udidRecordName) {
            let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if UUID(uuidString: s) != nil { return s }
        }
        return DeviceLayout.stableUDID(for: dir)
    }

    static let udidRecordName = "swiftcode-udid"

    static func family(typeID: String) -> PairingFamily {
        switch DeviceType.named(typeID)?.family {
        case .phone?: .phone
        case .watch?: .watch
        default: .other
        }
    }

    static func info(dir: String, set: String) throws -> PairingDevice {
        guard let typeID = DeviceLayout.recordedDeviceType(in: dir) else { throw NoDeviceType(dir: dir) }
        let name = DeviceType.named(typeID)?.name ?? typeID
        return PairingDevice(udid: udid(of: dir), directory: relative(dir, to: set), family: family(typeID: typeID),
                             typeName: name, osVersion: DeviceLayout.recordedRuntime(in: dir)?.version)
    }

    struct NoDeviceType: Error, CustomStringConvertible {
        let dir: String
        var description: String { "\(dir) has no device type yet: boot it once (with --device-type) before pairing it" }
    }

    static func relative(_ dir: String, to set: String) -> String {
        dir.hasPrefix(set + "/") ? String(dir.dropFirst(set.count + 1)) : dir
    }

    static func directory(record: String?, udid: String, set: String) -> String? {
        if let record {
            let d = record.hasPrefix("/") ? record : set + "/" + record
            if FileManager.default.fileExists(atPath: d) { return d }
        }
        return find(udid: udid, set: set)
    }

    static func find(udid: String, set: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: set)) ?? []
        return names.sorted().map { set + "/" + $0 }.first { d in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: d, isDirectory: &isDir) && isDir.boolValue
                && DeviceLayout.recordedDeviceType(in: d) != nil && Self.udid(of: d) == udid.uppercased()
        }
    }

    static func resolve(_ arg: String, set: String?) -> String? {
        let fm = FileManager.default
        if arg.contains("/") { return fm.fileExists(atPath: absolute(arg)) ? absolute(arg) : nil }
        guard let set else { return nil }
        if fm.fileExists(atPath: set + "/" + arg) { return set + "/" + arg }
        return UUID(uuidString: arg) != nil ? find(udid: arg, set: set) : nil
    }

    static func absolute(_ path: String) -> String {
        let p = path.hasPrefix("/") ? path : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path)
        return (p as NSString).standardizingPath
    }

    static func erase(_ dir: String) throws {
        let fm = FileManager.default
        let keep: Set<String> = ["swiftcode-device-type", udidRecordName]
        let trash = (dir as NSString).deletingLastPathComponent + "/.swiftcode-erased-\((dir as NSString).lastPathComponent)-\(getpid())"
        try fm.createDirectory(atPath: trash, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: dir) where !keep.contains(name) {
            try fm.moveItem(atPath: dir + "/" + name, toPath: trash + "/" + name)
        }
        try fm.removeItem(atPath: trash)
    }
}

#if os(Linux) && arch(arm64)
import Glibc

func isPairingCommand(_ arguments: [String]) -> Bool {
    arguments.contains { ["--pair", "--unpair", "--pair-activate", "--list-pairs"].contains($0) }
}

func runPairingCommand(_ arguments: [String]) -> Never {
    let help = """
        usage: swiftcode-simd [--device-set <dir>] --pair <watch> <phone>
               swiftcode-simd [--device-set <dir>] --unpair <pair UUID>
               swiftcode-simd [--device-set <dir>] --pair-activate <pair UUID>
               swiftcode-simd [--device-set <dir>] --list-pairs [--json]
        """
    var set = ProcessInfo.processInfo.environment["SWIFTCODE_DEVICE_SET"].flatMap { $0.isEmpty ? nil : absolutePath($0) }
    var verb = "", operands: [String] = [], json = false
    var i = 1
    while i < arguments.count {
        let a = arguments[i]
        switch a {
        case "--device-set":
            i += 1
            guard i < arguments.count else { die(help, status: 64) }
            set = absolutePath(arguments[i])
        case "--pair", "--unpair", "--pair-activate", "--list-pairs":
            guard verb.isEmpty else { die(help, status: 64) }
            verb = a
        case "--json": json = true
        default:
            guard !a.hasPrefix("--") else { die("unknown argument '\(a)'\n\(help)", status: 64) }
            operands.append(a)
        }
        i += 1
    }
    if set == nil, let first = operands.first(where: { $0.contains("/") }) {
        set = (absolutePath(first) as NSString).deletingLastPathComponent
    }
    guard let set else { die("swiftcode-simd: no device set (give --device-set, set SWIFTCODE_DEVICE_SET, or name a device by its path)\n\(help)", status: 64) }
    do {
        switch verb {
        case "--pair":
            guard operands.count == 2 else { die(help, status: 64) }
            let devices = try operands.map { arg -> PairingDevice in
                guard let dir = PairingDeviceDirectory.resolve(arg, set: set) else {
                    throw PairingCommandError("no device '\(arg)' (a device directory, its name in \(set), or a UDID)")
                }
                return try PairingDeviceDirectory.info(dir: dir, set: set)
            }
            let pair = try DevicePairStore.update(set: set) { try $0.pair(devices[0], devices[1]) }
            print(pair.id)
            for u in [pair.companion, pair.gizmo] { _ = PairSockets.command(udid: u, verb: "reload", timeout: 10) }
        case "--pair-activate":
            guard operands.count == 1 else { die(help, status: 64) }
            let pair = try DevicePairStore.update(set: set) { try $0.activate(operands[0]) }
            let others = (try DevicePairStore.load(set: set)).pairs.filter { $0.companion == pair.companion }.map(\.gizmo)
            var told = false
            for u in [pair.companion] + others where PairSockets.command(udid: u, verb: "reload", timeout: 10) != nil {
                told = told || u == pair.companion
            }
            stderrLine("swiftcode-simd: pair \(pair.id) is active" + (told ? "; the phone's guest switches in the background"
                + " (outcome: swiftcode-simd --device <phone> --control pairing state)" : "; the phone does not run"))
        case "--unpair":
            guard operands.count == 1 else { die(help, status: 64) }
            let pair = try DevicePairStore.update(set: set) { try $0.unpair(operands[0]) }
            try finishUnpair(pair, set: set)
        case "--list-pairs":
            guard operands.isEmpty else { die(help, status: 64) }
            let entries = try listing(set: set)
            print(json ? PairListing.json(entries) : PairListing.text(entries))
        default:
            die(help, status: 64)
        }
    } catch let e as PairingError {
        stderrLine("swiftcode-simd: \(e)")
        exit(e.exitStatus)
    } catch {
        stderrLine("swiftcode-simd: \(error)")
        exit(1)
    }
    exit(0)
}

struct PairingCommandError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

private func finishUnpair(_ pair: DevicePair, set: String) throws {
    if let answer = PairSockets.command(udid: pair.companion, verb: "unpair", args: [pair.gizmo], timeout: 300) {
        stderrLine("swiftcode-simd: phone: \(answer["text"] as? String ?? "?")")
    } else if let dir = PairingDeviceDirectory.directory(record: pair.companionDirectory, udid: pair.companion, set: set) {
        let path = dir + "/swiftcode-paired-peers"
        if let text = try? String(contentsOfFile: path, encoding: .utf8) {
            let rest = text.split(whereSeparator: \.isNewline).filter { $0.uppercased() != pair.gizmo }
            try? (rest.joined(separator: "\n") + (rest.isEmpty ? "" : "\n")).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    guard let watch = PairingDeviceDirectory.directory(record: pair.gizmoDirectory, udid: pair.gizmo, set: set) else {
        stderrLine("swiftcode-simd: the watch \(pair.gizmo) has no directory in \(set); nothing to erase")
        return
    }
    if PairSockets.command(udid: pair.gizmo, verb: "shutdown", args: ["unpaired"], timeout: 30) != nil {
        stderrLine("swiftcode-simd: watch: shutting down")
        let deadline = Date().addingTimeInterval(Double(ProcessInfo.processInfo.environment["SWIFTCODE_UNPAIR_SHUTDOWN_WAIT_S"] ?? "") ?? 180)
        while let fd = PairSockets.connect(udid: pair.gizmo) {
            close(fd)
            guard Date() < deadline else { throw PairingCommandError("the watch \(pair.gizmo) did not shut down; it was not erased") }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)
    }
    try PairingDeviceDirectory.erase(watch)
    print("erased \(watch)")
}

private func listing(set: String) throws -> [PairListingEntry] {
    let store = try DevicePairStore.load(set: set)
    var states: [String: [String: Any]] = [:]
    func state(_ udid: String) -> [String: Any]? {
        if let s = states[udid] { return s.isEmpty ? nil : s }
        let s = PairSockets.command(udid: udid, verb: "state", timeout: 5)?["state"] as? [String: Any]
        states[udid] = s ?? [:]
        return s
    }
    func side(_ udid: String, _ record: String?) -> PairListingEntry.Side {
        let dir = PairingDeviceDirectory.directory(record: record, udid: udid, set: set)
        let type = dir.flatMap(DeviceLayout.recordedDeviceType(in:)).flatMap(DeviceType.named)?.name ?? "?"
        let name = dir.map { "\(type) [\(($0 as NSString).lastPathComponent)]" } ?? "\(type) [missing]"
        return .init(name: name, udid: udid, state: state(udid) != nil ? "Booted" : "Shutdown")
    }
    return store.pairs.map { p in
        let watch = side(p.gizmo, p.gizmoDirectory), phone = side(p.companion, p.companionDirectory)
        let peers = state(p.gizmo)?["peers"] as? [String: Any]
        let connected = (peers?[p.companion] as? [String: Any])?["connected"] as? Bool ?? false
        return PairListingEntry(id: p.id, watch: watch, phone: phone, active: p.active, connected: connected && phone.state == "Booted")
    }
}
#endif
