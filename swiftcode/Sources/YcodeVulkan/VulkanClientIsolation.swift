import CVulkan
import Foundation
import YcodeMetalHost

extension VulkanMetalBackend {
    struct BlockedClients {
        var stuck: MetalProcessID?
        var others: [MetalProcessID: Int] = [:]
        var label = ""
    }

    func blockedClients(behind serial: UInt64) -> BlockedClients {
        let first = pending.first { $0.serial >= serial && $0.commandBuffer != nil }
        var b = BlockedClients(stuck: first?.commandBuffer?.process, label: first?.label ?? pending.first?.label ?? "")
        func note(_ p: MetalProcessID?) {
            guard let p, p != b.stuck else { return }
            b.others[p, default: 0] += 1
        }
        for e in pending where e.serial > serial || (e.serial == serial && e.commandBuffer?.process != b.stuck) {
            note(e.commandBuffer?.process)
        }
        for item in parked { note(item.commandBuffer?.process) }
        return b
    }

    func watchdogReason(serial: UInt64, ran: Double) -> (reason: String, blocked: BlockedClients)? {
        let plain = options.watchdogSeconds > 0 && ran >= options.watchdogSeconds
        let blocking = options.blockingWatchdogSeconds > 0 && ran >= options.blockingWatchdogSeconds
        guard plain || blocking else { return nil }
        cond.lock()
        let b = blockedClients(behind: serial)
        cond.unlock()
        if !b.others.isEmpty && blocking {
            let n = b.others.values.reduce(0, +)
            return ("\(n) command buffer\(n == 1 ? "" : "s") of \(b.others.count) other client\(b.others.count == 1 ? "" : "s") "
                    + "waited behind it (\(b.others.keys.sorted().map(describeClient).joined(separator: ", ")))", b)
        }
        return plain ? ("the watchdog's limit is \(Self.seconds(options.watchdogSeconds))", b) : nil
    }

    func describeClient(_ p: MetalProcessID?) -> String {
        guard let p else { return "SwiftCode's own work" }
        cond.lock()
        var name = clientNames[p]
        cond.unlock()
        if name == nil, let d = options.describeProcess?(p) {
            name = d
            cond.lock(); clientNames[p] = d; cond.unlock()
        }
        return "process \(p)" + (name.map { " (\($0))" } ?? "")
    }

    func knownClient(_ p: MetalProcessID) -> String {
        "process \(p)" + (clientNames[p].map { " (\($0))" } ?? "")
    }

    static func seconds(_ s: Double) -> String { String(format: "%.1f s", s) }

    func blameStuckClient(_ items: inout [ResubmitItem]) -> (process: MetalProcessID, failed: Int, hangs: Int)? {
        guard let guilty = items.first(where: \.guilty), let p = guilty.commandBuffer?.process else { return nil }
        var failed = 0
        for i in items.indices where items[i].commandBuffer?.process == p {
            items[i].guilty = true
            failed += 1
        }
        hangsByProcess[p, default: 0] += 1
        statistics.clientHangs += 1
        return (p, failed, hangsByProcess[p]!)
    }

    func revokeIfDue(_ process: MetalProcessID, hangs: Int) {
        guard options.revokeAfterHangs > 0, hangs >= options.revokeAfterHangs else { return }
        let exempt = options.exemptFromRevocation?(process) ?? false
        cond.lock()
        let already = revokedProcesses.contains(process)
        if exempt {
            statistics.exemptFromRevocation += 1
        } else if !already {
            revokedProcesses.insert(process)
            statistics.revokedClients += 1
        }
        cond.unlock()
        if exempt {
            log("GPU access kept for \(describeClient(process)) after \(hangs) GPU hangs: the system UI is never revoked "
                + "(its stuck work is ended each time)")
        } else if !already {
            log("GPU access revoked for \(describeClient(process)) after \(hangs) GPU hangs: "
                + "its later command buffers fail without running")
        }
    }

    func refuseRevoked(_ mcb: MetalCommandBuffer, scheduled: @escaping @Sendable () -> Void,
                       completed: @escaping @Sendable (Int) -> Void) -> Bool {
        guard revokedProcesses.contains(mcb.process) else { return false }
        refusedByProcess[mcb.process, default: 0] += 1
        statistics.revokedRefusals += 1
        let n = refusedByProcess[mcb.process]!
        if n == 1 || n % 1000 == 0 {
            log("GPU access revoked: command buffer \(mcb.commandBufferRef) of \(knownClient(mcb.process)) fails without running "
                + "(\(n) so far)")
        }
        enqueueCompletion(status: MetalCommandBufferStatus.error, scheduled: scheduled, completed: completed)
        return true
    }

    func kickGPU() -> String {
        guard options.kick else { return "off" }
        let start = DispatchTime.now().uptimeNanoseconds
        if kicker == nil {
            let c = UnsafeMutablePointer<yvk_context>.allocate(capacity: 1)
            c.initialize(to: yvk_context())
            var opts = yvk_context_options(maxSampledImages: 16, maxSamplers: 16, maxStorageImages: 16, validation: 0,
                                           queues: 1, second: 1)
            var err = [CChar](repeating: 0, count: 512)
            guard yvk_context_create(c, &opts, &err, err.count) == 0 else {
                c.deallocate()
                return "no second device (\(cString(err)))"
            }
            kicker = c
        }
        let made = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        let r = yvk_kick(kicker, 15_000_000_000)
        let ran = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        if r != VK_SUCCESS {
            if r == VK_ERROR_DEVICE_LOST, let k = kicker { yvk_context_destroy(k); k.deallocate() }
            kicker = nil
        }
        return String(format: "%@ after %.1f s (second device %@)", r == VK_SUCCESS ? "ran" : "failed (\(r.rawValue))", ran,
                      made > 0.001 ? String(format: "made in %.1f s", made) : "kept")
    }

    func destroyKicker() {
        guard let k = kicker else { return }
        kicker = nil
        yvk_context_destroy(k)
        k.deallocate()
    }

    public func gpuAccessRevoked(_ p: MetalProcessID) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return revokedProcesses.contains(p)
    }

    public var lastHangReport: String {
        cond.lock(); defer { cond.unlock() }
        return lastHang
    }
}
