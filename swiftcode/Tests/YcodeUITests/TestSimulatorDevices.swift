import Foundation
@testable import YcodeIDECore
@testable import YcodeUI

enum TestSimulatorDevices {
    static let prefix = "swiftcode-test-"
    static let suitePrefix = "swiftcode-test-ide-"
    typealias Runner = @Sendable ([String]) -> (Int32, String)

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var udids: Set<String> = []
    }
    private static let registry = Registry()

    static var created: Set<String> { registry.lock.withLock { registry.udids } }
    static func record(_ udid: String) { _ = registry.lock.withLock { registry.udids.insert(udid) } }
    static func forget(_ udid: String) { _ = registry.lock.withLock { registry.udids.remove(udid) } }

    static func newName(pid: Int32 = getpid()) -> String { "\(suitePrefix)\(pid)-\(UUID().uuidString)" }

    static func mayRemove(name: String, udid: String, created: Set<String>) -> Bool {
        name.hasPrefix(prefix) && created.contains(udid)
    }

    static func suitePID(_ name: String) -> Int32? {
        guard name.hasPrefix(suitePrefix) else { return nil }
        let rest = name.dropFirst(suitePrefix.count)
        guard let dash = rest.firstIndex(of: "-"), let pid = Int32(rest[..<dash]), pid > 0,
              UUID(uuidString: String(rest[rest.index(after: dash)...])) != nil else { return nil }
        return pid
    }

    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    static func staleCandidates(_ devices: [(name: String, udid: String)], ownPID: Int32 = getpid(),
                                isAlive: (Int32) -> Bool = isAlive) -> [String] {
        devices.compactMap { d in
            guard let pid = suitePID(d.name), pid != ownPID, !isAlive(pid) else { return nil }
            return d.udid
        }
    }

    static func list(_ run: Runner) -> [(name: String, udid: String)] {
        let (s, out) = run(["list", "-j", "devices"])
        guard s == 0, let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let byRuntime = obj["devices"] as? [String: [[String: Any]]] else { return [] }
        return byRuntime.values.flatMap { $0 }.compactMap { d in
            guard let name = d["name"] as? String, let udid = d["udid"] as? String else { return nil }
            return (name, udid)
        }
    }

    @discardableResult
    static func remove(udid: String, run: Runner = Simctl.xcrun) -> Bool {
        guard let device = list(run).first(where: { $0.udid == udid }) else {
            forget(udid)
            return false
        }
        guard mayRemove(name: device.name, udid: udid, created: created) else {
            FileHandle.standardError.write(Data("TestSimulatorDevices: refusing to remove \(device.name) (\(udid)): not a device this test made\n".utf8))
            return false
        }
        _ = run(["shutdown", udid])
        _ = run(["delete", udid])
        forget(udid)
        return true
    }

    static func sweepStale(run: Runner = Simctl.xcrun, isAlive: (Int32) -> Bool = isAlive) {
        for udid in staleCandidates(list(run), isAlive: isAlive) {
            _ = run(["shutdown", udid])
            _ = run(["delete", udid])
        }
    }
}
