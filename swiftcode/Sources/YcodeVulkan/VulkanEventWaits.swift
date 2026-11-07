import CVulkan
import Foundation
import YcodeMetalHost

struct HeldKey: Hashable {
    var process: MetalProcessID
    var queue: MetalHandle?
}

enum HeldItem {
    case wait(VkSemaphore, UInt64)
    case submit(Recording, VulkanMetalBackend.PendingSubmission?)
    case signal(VkSemaphore, UInt64)
}

final class SubmitSink {
    let key: HeldKey
    var holding: Bool
    var items: [HeldItem] = []
    var surfacesIn: [UInt32] = [], surfacesOut: [UInt32] = []
    var earlierDraws = 0
    var traceSlot = -1
    var segments: [String] = []
    init(key: HeldKey, holding: Bool) {
        self.key = key
        self.holding = holding
    }
}

extension VulkanMetalBackend {
    func sinkSubmit(_ sink: SubmitSink, _ rec: Recording, entry: PendingSubmission?) throws {
        if sink.holding {
            rec.deferred = true
            _ = fn.vkEndCommandBuffer!(rec.cb)
            sink.items.append(.submit(rec, entry))
        } else {
            try submitRecording(rec, entry: entry)
        }
    }

    func sinkWait(_ sink: SubmitSink, _ sem: VkSemaphore, value: UInt64) -> Bool {
        if !sink.holding && yvk_timeline_value(ctx, sem) >= value { return false }
        sink.holding = true
        sink.items.append(.wait(sem, value))
        return true
    }

    func sinkSignal(_ sink: SubmitSink, _ sem: VkSemaphore, value: UInt64) {
        if sink.holding {
            sink.items.append(.signal(sem, value))
        } else {
            _ = yvk_submit(ctx, nil, sem, value, nil, 0)
        }
    }

    func hold(_ sink: SubmitSink) {
        guard !sink.items.isEmpty else { return }
        if held[sink.key] == nil { heldSince[sink.key] = DispatchTime.now().uptimeNanoseconds }
        held[sink.key, default: []].append(contentsOf: sink.items)
        sink.items.removeAll()
        if heldThread == nil {
            let thread = Thread { [unowned self] in self.heldLoop() }
            thread.name = "swiftcode-vulkan-held"
            heldThread = thread
            thread.start()
        }
        cond.broadcast()
    }

    func heldLoop() {
        cond.lock()
        while running {
            if held.isEmpty {
                cond.wait(until: Date(timeIntervalSinceNow: 0.05))
                continue
            }
            releaseHeldLocked()
            if !held.isEmpty { cond.wait(until: Date(timeIntervalSinceNow: 0.001)) }
        }
        for items in held.values {
            for case let .submit(rec, entry) in items {
                if let cb = rec.cb { freeCommandBuffers.append(cb) }
                for c in rec.chunks { recycle(c) }
                if let entry {
                    enqueueCompletion(status: MetalCommandBufferStatus.error, scheduled: entry.scheduled,
                                      completed: entry.completed)
                }
            }
        }
        held.removeAll()
        releaseHeldGraveyardLocked()
        heldThread = nil
        cond.broadcast()
        cond.unlock()
    }

    func releaseHeldLocked() {
        let now = DispatchTime.now().uptimeNanoseconds
        for key in Array(held.keys) {
            var items = held[key] ?? []
            steps: while let first = items.first {
                switch first {
                case .wait(let sem, let value):
                    let current = yvk_timeline_value(ctx, sem)
                    guard current >= value || deviceLost else {
                        let since = heldSince[key] ?? now
                        let seconds = (now &- since) / 1_000_000_000
                        if seconds >= 10, (heldReported[key] ?? 0) < seconds / 10 {
                            heldReported[key] = seconds / 10
                            log("process \(key.process) queue \(key.queue.map { "\($0)" } ?? "-"): held \(seconds) s "
                                + "waiting for an event to reach \(value) (now \(current)); \(items.count) steps held")
                        }
                        break steps
                    }
                    items.removeFirst()
                    heldSince[key] = now
                    heldReported[key] = nil
                case .submit(let rec, let entry):
                    items.removeFirst()
                    do {
                        try submitPreparedRecording(rec, entry: entry)
                    } catch {
                        log("held command buffer of process \(key.process): \(error)")
                        if let cb = rec.cb { freeCommandBuffers.append(cb) }
                        for c in rec.chunks { recycle(c) }
                        if let entry, !(deviceLost && parkForReset(entry.commandBuffer, scheduled: entry.scheduled,
                                                                   completed: entry.completed)) {
                            enqueueCompletion(status: MetalCommandBufferStatus.error, scheduled: entry.scheduled,
                                              completed: entry.completed)
                        }
                    }
                case .signal(let sem, let value):
                    items.removeFirst()
                    if value > yvk_timeline_value(ctx, sem) { _ = yvk_submit(ctx, nil, sem, value, nil, 0) }
                }
            }
            if items.isEmpty {
                held[key] = nil
                heldSince[key] = nil
                heldReported[key] = nil
            } else {
                held[key] = items
            }
        }
        if held.isEmpty { releaseHeldGraveyardLocked() }
    }

    func releaseHeldGraveyardLocked() {
        guard !heldGraveyard.isEmpty else { return }
        let actions = heldGraveyard
        heldGraveyard.removeAll()
        for a in actions { deferDestroy(a) }
    }
}
