import CVulkan
import Foundation
import SwiftCodeMetalHost

extension VulkanMetalBackend {

    func enterDevice() {
        gate.lock()
        while gateClosed { gate.wait() }
        gateUsers += 1
        gate.unlock()
    }

    func leaveDevice() {
        gate.lock()
        gateUsers -= 1
        if gateUsers == 0 { gate.broadcast() }
        gate.unlock()
    }

    public func setDeviceResetHandler(_ handler: @escaping @Sendable () -> Void) {
        cond.lock(); defer { cond.unlock() }
        deviceResetHandler = handler
    }

    var canRecover: Bool { options.recoverDevice && !recoveryGivenUp && running }

    public var deviceResetCount: Int {
        cond.lock(); defer { cond.unlock() }
        return deviceResets
    }

    public var lastDeviceResetReport: String {
        cond.lock(); defer { cond.unlock() }
        return lastResetReport
    }

    struct ResubmitItem {
        var commandBuffer: MetalCommandBuffer?
        var status = MetalCommandBufferStatus.completed
        var scheduled: (@Sendable () -> Void)?
        var completed: (@Sendable (Int) -> Void)?
        var after: ((Bool) -> Void)?
        var guilty: Bool
    }

    func parkForReset(_ mcb: MetalCommandBuffer?, scheduled: (@Sendable () -> Void)?,
                      completed: (@Sendable (Int) -> Void)?) -> Bool {
        guard canRecover, let mcb else { return false }
        parked.append(ResubmitItem(commandBuffer: mcb, scheduled: scheduled, completed: completed, after: nil, guilty: false))
        cond.broadcast()
        return true
    }

    func recoverDevice(stuckSerial: UInt64) {
        let started = DispatchTime.now().uptimeNanoseconds
        var phases: [String] = []
        var phaseStart = started
        func phase(_ name: String) {
            let now = DispatchTime.now().uptimeNanoseconds
            phases.append(String(format: "%@ %.0f", name, Double(now &- phaseStart) / 1e6))
            phaseStart = now
        }
        gate.lock()
        gateClosed = true
        while gateUsers > 0 { gate.wait() }
        gate.unlock()
        phase("gate")

        cond.lock()
        let fired = watchdogFired
        watchdogFired = false
        deviceLost = true
        _ = fn.vkDeviceWaitIdle!(ctx.pointee.device)
        phase("idle")

        var items: [ResubmitItem] = []
        var guiltyFound = false
        var oldChunks: [TransientChunk] = []
        for e in pending.sorted(by: { $0.serial < $1.serial }) {
            oldChunks += e.chunks
            if let t = e.trace, let ft = frameTrace { ft.release(t.slot) }
            let guilty = !guiltyFound && e.commandBuffer != nil && e.serial >= stuckSerial
            if guilty { guiltyFound = true }
            items.append(ResubmitItem(commandBuffer: e.commandBuffer, status: e.status, scheduled: e.scheduled,
                                      completed: e.completed, after: e.after, guilty: guilty))
        }
        pending.removeAll()
        for key in held.keys.sorted(by: { ($0.process, $0.queue?.raw ?? 0) < ($1.process, $1.queue?.raw ?? 0) }) {
            for case let .submit(rec, entry) in held[key] ?? [] {
                oldChunks += rec.chunks
                guard let entry else { continue }
                items.append(ResubmitItem(commandBuffer: entry.commandBuffer, status: entry.status, scheduled: entry.scheduled,
                                          completed: entry.completed, after: entry.after, guilty: false))
            }
        }
        held.removeAll()
        heldSince.removeAll()
        heldReported.removeAll()
        items += parked
        parked.removeAll()
        if let s = setup { oldChunks += s.chunks }
        setup = nil
        let blamed = blameStuckClient(&items)
        for i in items.indices {
            items[i].after?(false)
            items[i].after = nil
        }

        while !graveyard.isEmpty || !heldGraveyard.isEmpty {
            let deferred = graveyard.map(\.action) + heldGraveyard
            graveyard.removeAll()
            heldGraveyard.removeAll()
            for a in deferred { a() }
        }

        phase("work")
        var allocations: [ObjectIdentifier: VKAllocation] = [:]
        func addAllocation(_ a: VKAllocation) { allocations[ObjectIdentifier(a)] = a }
        for b in buffers.values { addAllocation(b.allocation) }
        for a in imports.values { addAllocation(a) }
        var images: [ObjectIdentifier: VKImage] = [:]
        for t in textures.values {
            images[ObjectIdentifier(t.image)] = t.image
            if let s = t.image.surface { addAllocation(s.allocation) }
        }
        var saved: [ObjectIdentifier: Data] = [:]
        var capture: [ObjectIdentifier: (address: UInt64, captureAddress: UInt64, size: VkDeviceSize)] = [:]
        for (id, a) in allocations {
            capture[id] = (a.buffer.address, a.buffer.captureAddress, a.buffer.size)
            if a.key == nil, let p = a.buffer.mapped, a.buffer.size > 0 { saved[id] = Data(bytes: p, count: Int(a.buffer.size)) }
        }
        let device = ctx.pointee.device
        for a in allocations.values { yvk_buffer_destroy(ctx, &a.buffer) }
        for t in textures.values { destroyViews(t) }
        for i in images.values { yvk_image_destroy(ctx, &i.image) }
        for t in feedbackCopies.values {
            destroyViews(t)
            yvk_image_destroy(ctx, &t.image.image)
            if t.heapIndex != 0 { textureIndices.release(t.heapIndex, count: max(t.heapCount, 1)) }
        }
        feedbackCopies.removeAll()
        textureOverride.removeAll()
        var samplerObjects: [ObjectIdentifier: VKSampler] = [:]
        for s in samplerCache.values { samplerObjects[ObjectIdentifier(s)] = s }
        for s in samplers.values { samplerObjects[ObjectIdentifier(s)] = s }
        for s in samplerObjects.values {
            if let v = s.sampler { fn.vkDestroySampler!(device, v, nil) }
            s.sampler = nil
        }
        var eventObjects: [ObjectIdentifier: VKEvent] = [:]
        for e in events.values { eventObjects[ObjectIdentifier(e)] = e }
        for e in eventObjects.values {
            if let s = e.semaphore { fn.vkDestroySemaphore!(device, s, nil) }
            e.semaphore = nil
        }
        for p in renderPipelines.values {
            for v in p.variants.values { fn.vkDestroyPipeline!(device, v, nil) }
            p.variants.removeAll()
            p.failed.removeAll()
            for a in p.vertexStatics.memory + p.fragmentStatics.memory { yvk_buffer_destroy(ctx, &a.buffer) }
            p.vertexStatics = StageStatics()
            p.fragmentStatics = StageStatics()
        }
        for p in computePipelines.values {
            for v in p.variants.values { fn.vkDestroyPipeline!(device, v, nil) }
            p.variants.removeAll()
            p.failed.removeAll()
            for a in p.statics.memory { yvk_buffer_destroy(ctx, &a.buffer) }
            p.statics = StageStatics()
        }
        for p in libraries.removeAll() { fn.vkDestroyPipeline!(device, p, nil) }
        for c in oldChunks + freeChunks { yvk_buffer_destroy(ctx, &c.buffer) }
        freeChunks.removeAll()
        freeCommandBuffers.removeAll()
        for p in freeVisibilityPools { fn.vkDestroyQueryPool!(device, p, nil) }
        freeVisibilityPools.removeAll()
        if let ft = frameTrace {
            ft.destroy(device, fn)
            frameTrace = nil
            log("frame trace: stopped by the device reset")
        }
        if let p = probe { yvk_buffer_destroy(ctx, &p.buffer); probe = nil }
        depthTapDeviceLost(device)
        if let s = defaultSampler { fn.vkDestroySampler!(device, s, nil) }
        defaultSampler = nil
        if let v = dummyView { fn.vkDestroyImageView!(device, v, nil) }
        dummyView = nil
        if let d = dummyImage { yvk_image_destroy(ctx, &d.image) }
        dummyImage = nil
        yvk_buffer_destroy(ctx, &dummyBuffer)
        if let t = timeline { fn.vkDestroySemaphore!(device, t, nil) }
        timeline = nil

        phase("objects")
        yvk_context_destroy(ctx)
        phase("destroy")
        var opts = yvk_context_options(maxSampledImages: options.maxSampledImages, maxSamplers: options.maxSamplers,
                                       maxStorageImages: options.maxStorageImages, validation: options.validation ? 1 : 0,
                                       queues: 1, second: 0)
        var err = [CChar](repeating: 0, count: 512)
        let created = yvk_context_create(ctx, &opts, &err, err.count) == 0
        fn = yvk_fns().pointee
        timeline = created ? yvk_timeline_create(ctx, 0) : nil
        guard created, timeline != nil else {
            let why = created ? "timeline semaphore creation failed" : cString(err)
            lastResetReport = "the device could not be made again: \(why)"
            log("device reset: " + lastResetReport)
            recoveryGivenUp = true
            cond.unlock()
            reopenGate()
            finish(items, resubmit: false)
            return
        }
        lastSubmitted = 0
        completedSerial = 0
        phase("create")

        var failures: [String] = []
        var moved = 0
        for (id, a) in allocations {
            guard let old = capture[id] else { continue }
            var b = yvk_buffer()
            let host: UnsafeMutableRawPointer? = a.key.flatMap { UnsafeMutableRawPointer(bitPattern: $0.start) }
            let size = a.key.map { VkDeviceSize($0.length) } ?? max(old.size, 4)
            if yvk_buffer_recreate(ctx, size, a.kind, host, old.captureAddress, &b, &err, err.count) == 0 {
                a.buffer = b
                if a.key == nil { a.base = b.mapped }
                if b.address != old.address { moved += 1 }
                if let d = saved[id], let p = b.mapped {
                    d.withUnsafeBytes { p.copyMemory(from: $0.baseAddress!, byteCount: min(d.count, Int(b.size))) }
                }
            } else if failures.count < 8 {
                failures.append("buffer: \(cString(err))")
            }
        }
        do {
            try createDummiesLocked()
        } catch {
            failures.append("dummy resources: \(error)")
        }
        createPipelineCache()
        for image in images.values {
            var info = image.createInfo
            var img = yvk_image()
            if yvk_image_create(ctx, &info, &img, &err, err.count) == 0 {
                image.image = img
                image.syncedGeneration = nil
                do { try initializeImage(image) } catch { failures.append("image layout: \(error)") }
            } else if failures.count < 8 {
                failures.append("image \(image.width)x\(image.height): \(cString(err))")
            }
        }
        for (h, t) in textures where t.textureType != MetalTextureType.typeTextureBuffer {
            makeShaderViews(t, handle: h, keepSlot: true)
        }
        for s in samplerObjects.values {
            var info = samplerInfo(s.key)
            s.sampler = yvk_sampler_create(ctx, &info, &err, err.count)
            if let v = s.sampler { yvk_heap_write_sampler(ctx, s.heapIndex, v) } else if failures.count < 8 {
                failures.append("sampler: \(cString(err))")
            }
        }
        for e in eventObjects.values { e.semaphore = yvk_timeline_create(ctx, e.highest) }
        for p in renderPipelines.values {
            do {
                if let v = p.vertex { p.vertexStatics = try statics(for: v.reflection) }
                if let f = p.fragment { p.fragmentStatics = try statics(for: f.reflection) }
            } catch {
                failures.append("render pipeline constants: \(error)")
            }
        }
        for p in computePipelines.values {
            guard let s = p.shader else { continue }
            do { p.statics = try statics(for: s.reflection) } catch { failures.append("compute pipeline constants: \(error)") }
        }
        try? flushSetup()
        phase("rebuild")

        checkpointRecords.removeAll()
        surfaceWriteSerials.removeAll()
        surfaceWaitStuckAt = nil
        releasedBufferRanges.removeAll()
        deviceLost = false
        deviceLossReported = false
        deviceResets += 1
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e6
        let resubmitted = items.filter { !$0.guilty && $0.commandBuffer != nil }.count
        lastResetReport = String(format: "device made again in %.0f ms (reset %d, %@): ", ms, deviceResets,
                                 fired ? "after the watchdog" : "after a device loss")
            + "\(allocations.count) buffers and imports (\(moved) at a new device address), \(images.count) images, "
            + "\(textures.count) textures, \(samplerObjects.count) samplers, \(eventObjects.count) events, "
            + "\(renderPipelines.count) render and \(computePipelines.count) compute pipelines; "
            + "\(items.filter(\.guilty).count) command buffer(s) failed"
            + (blamed.map { " (\(knownClient($0.process))'s)" } ?? "") + ", \(resubmitted) recorded again"
            + (failures.isEmpty ? "" : "; failures: " + failures.joined(separator: "; "))
            + " (ms: " + phases.joined(separator: ", ") + ")"
        log(lastResetReport)
        cond.broadcast()
        cond.unlock()
        reopenGate()
        cond.lock()
        let handler = deviceResetHandler
        cond.unlock()
        handler?()
        if let b = blamed { revokeIfDue(b.process, hangs: b.hangs) }
        finish(items, resubmit: true)
    }

    private func reopenGate() {
        gate.lock()
        gateClosed = false
        gate.broadcast()
        gate.unlock()
    }

    private func finish(_ items: [ResubmitItem], resubmit: Bool) {
        for item in items {
            guard resubmit, !item.guilty, let mcb = item.commandBuffer else {
                let ok = resubmit && !item.guilty && item.commandBuffer == nil
                item.scheduled?()
                item.completed?(ok ? item.status : MetalCommandBufferStatus.error)
                continue
            }
            submit(mcb, scheduled: item.scheduled ?? {}, completed: item.completed ?? { _ in })
        }
    }

    private func destroyViews(_ t: VKTexture) {
        let device = ctx.pointee.device
        for v in [t.shaderView, t.storageView].compactMap({ $0 }) + t.levelStorageViews + t.attachmentViews.values.compactMap({ $0 }) {
            fn.vkDestroyImageView!(device, v, nil)
        }
        t.shaderView = nil
        t.storageView = nil
        t.levelStorageViews.removeAll()
        t.attachmentViews.removeAll()
    }
}
