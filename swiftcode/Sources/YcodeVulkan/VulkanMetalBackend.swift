import CVulkan
import Foundation
import YcodeMetalHost

public struct VulkanBackendError: Error, CustomStringConvertible, Sendable {
    public var description: String
    public init(_ d: String) { description = d }
}

public final class VulkanMetalBackend: MetalBackend, @unchecked Sendable {
    public struct Options: Sendable {
        public var maxSampledImages: UInt32 = 0
        public var maxSamplers: UInt32 = 0
        public var maxStorageImages: UInt32 = 0
        public var validation = false
        public var transientChunkSize = 4 << 20
        public var log: (@Sendable (String) -> Void)?
        public var asynchronousPipelines = true
        public var compileThreads = 4
        public var translatorProcesses = ProcessInfo.processInfo.environment["SWIFTCODE_AIRC_PROCESSES"].flatMap { Int($0) }.map { max($0, 1) } ?? 4
        public var pipelineCachePath: String? = ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_PIPELINE_CACHE"]
        public var surfaceDamage = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_SURFACE_DAMAGE"] != "0"
        public var surfaceSkipCopyIn = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_SURFACE_SKIP_IN"] != "0"
        public var completionPollNs: UInt64 = UInt64(ProcessInfo.processInfo.environment["SWIFTCODE_GPU_COMPLETION_POLL_US"]
            .flatMap { UInt64($0) }.map { max($0, 50) } ?? 1000) * 1000
        public var earlyScheduled = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_EARLY_SCHEDULED"] != "0"
        public var surfaceWaitPollNs: UInt64 = UInt64(ProcessInfo.processInfo.environment["SWIFTCODE_GPU_SURFACE_WAIT_POLL_US"]
            .flatMap { UInt64($0) } ?? 200) * 1000
        public var laneIsolatedKernels: Set<String> = Set((ProcessInfo.processInfo.environment["SWIFTCODE_GPU_LANE_ISOLATED"] ?? "astc")
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        public var importSlack = (Int(ProcessInfo.processInfo.environment["SWIFTCODE_GPU_IMPORT_SLACK_KB"] ?? "") ?? 0) * 1024
        public var importSlackWindow: (UInt, UInt)?
        public var feedbackSnapshots = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_FEEDBACK_COPY"] != "0"
        public var feedbackWholeLevel = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_FEEDBACK_COPY"] == "whole"
        public var pipelineCacheSaveInterval = 15.0
        public var shutdownGrace = 10.0
        public var hangReportSeconds = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_HANG_REPORT_S"].flatMap { Double($0) } ?? 2
        public var watchdogSeconds = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_WATCHDOG_S"].flatMap { Double($0) } ?? 10
        public var blockingWatchdogSeconds = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_BLOCKING_WATCHDOG_S"]
            .flatMap { Double($0) } ?? 2
        public var revokeAfterHangs = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_REVOKE_AFTER"].flatMap { Int($0) } ?? 2
        public var describeProcess: (@Sendable (MetalProcessID) -> String?)?
        public var exemptFromRevocation: (@Sendable (MetalProcessID) -> Bool)?
        public var recoverDevice = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_RECOVER"] != "0"
        public var kick = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_KICK"] != "0"
        public var unboundBuffersReadDummy = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_UNBOUND_DUMMY"] != "0"
        public var recordFast = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_RECORD_FAST"] != "0"
        public var skipShaders: Set<String> = Set((ProcessInfo.processInfo.environment["SWIFTCODE_GPU_SKIP_SHADERS"] ?? "")
            .split(separator: ",").map { String($0) })
        public init() {}
    }

    public let isAvailable: Bool
    public let unavailableReason: String?
    public let deviceName: String
    public let options: Options

    let ctx: UnsafeMutablePointer<yvk_context>
    var fn: yvk_dispatch
    let translator: ShaderTranslator?
    let cond = NSCondition()

    var buffers: [MetalHandle: VKBuffer] = [:]
    var textures: [MetalHandle: VKTexture] = [:]
    var samplers: [MetalHandle: VKSampler] = [:]
    var samplerCache: [SamplerKey: VKSampler] = [:]
    var depthStencilStates: [MetalHandle: MetalDepthStencilDescriptor] = [:]
    var functions: [MetalHandle: VKFunction] = [:]
    var renderPipelines: [MetalHandle: VKRenderPipeline] = [:]
    var computePipelines: [MetalHandle: VKComputePipeline] = [:]
    var events: [MetalHandle: VKEvent] = [:]
    var imports: [AllocationKey: VKAllocation] = [:]
    var imageReferences: [ObjectIdentifier: Int] = [:]
    var formatCache: [UInt32: VulkanPixelFormat?] = [:]
    var textureIndices: IndexAllocator
    var samplerIndices: IndexAllocator
    var reservedTextureSlots: [MetalHandle: (index: UInt32, count: UInt32)] = [:]
    var reservedSamplerSlots: [MetalHandle: UInt32] = [:]
    var reservedSamplerIndices: Set<UInt32> = []
    var dummyImage: VKImage?
    var dummyView: VkImageView?
    var writesWithoutUsageSeen: Set<String> = []
    var writesWithoutUsageLogged = 0
    var unboundBuffersSeen: Set<String> = []
    var mixedSizeLogs = 0
    var defaultSampler: VkSampler?
    var dummyBuffer = yvk_buffer()
    var dummyBufferAddress: UInt64 { dummyBuffer.address }

    let translationLock = NSLock()
    var translations: [TranslationKey: TranslatedShader] = [:]

    var timeline: VkSemaphore?
    var lastSubmitted: UInt64 = 0
    var completedSerial: UInt64 = 0
    var setup: Recording?
    var freeCommandBuffers: [VkCommandBuffer] = []
    var freeChunks: [TransientChunk] = []
    var freeVisibilityPools: [VkQueryPool] = []
    var debugReplayProcess: MetalProcessID = 0
    var pending: [PendingSubmission] = []
    var graveyard: [(serial: UInt64, action: () -> Void)] = []
    var deviceLost = false
    var deviceResets = 0
    var lastResetReport = ""
    var watchdogFired = false
    var hangsByProcess: [MetalProcessID: Int] = [:]
    var revokedProcesses: Set<MetalProcessID> = []
    var refusedByProcess: [MetalProcessID: Int] = [:]
    var clientNames: [MetalProcessID: String] = [:]
    var lastHang = ""
    var hangInjection = HangInjection(ProcessInfo.processInfo.environment["SWIFTCODE_GPU_INJECT_HANG"])
    let startedAt = DispatchTime.now().uptimeNanoseconds
    var kicker: UnsafeMutablePointer<yvk_context>?
    let injectsHangs = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_INJECT_HANG"] != nil
    var parked: [ResubmitItem] = []
    var recoveryGivenUp = false
    var deviceResetHandler: (@Sendable () -> Void)?
    let gate = NSCondition()
    var gateUsers = 0
    var gateClosed = false
    var running = true
    var completionThread: Thread?
    var shutdownDeadline: UInt64 = .max
    var abandonedAtShutdown = false
    var statistics = VulkanBackendStatistics()
    var skipLines: [Int: Int] = [:]

    let compileQueue = OperationQueue()
    let libraries = PipelineLibraryCache()
    var pipelineCacheDirty = false
    var cacheTimer: DispatchSourceTimer?

    struct PendingSubmission {
        var serial: UInt64
        var cb: VkCommandBuffer?
        var chunks: [TransientChunk]
        var status: Int
        var scheduled: (@Sendable () -> Void)?
        var completed: (@Sendable (Int) -> Void)?
        var after: ((_ ok: Bool) -> Void)?
        var queuedAt: UInt64 = DispatchTime.now().uptimeNanoseconds
        var label: String = ""
        var trace: FrameTraceInfo?
        var commandBuffer: MetalCommandBuffer?
        var dispatchTables: [(pass: Int, command: Int, table: UnsafeMutableRawPointer)] = []
    }

    var surfaceGenerations: [SurfaceSyncKey: UInt64] = [:]
    var earlyScheduledQueue: [@Sendable () -> Void] = []
    let flushingScheduled = NSLock()
    var scheduledFlushRunning = false
    var surfaceWriteSerials: [UInt32: UInt64] = [:]
    var surfaceWaitStuckAt: UInt64?

    var invalidCopyLogBudget = 20

    var damageLogBudget = Int(ProcessInfo.processInfo.environment["SWIFTCODE_GPU_DAMAGE_LOG"] ?? "") ?? 0

    var frameTrace: FrameTrace?
    var depthTapStorage: AnyObject?

    let recordProfiling = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_RECORD_PROFILE"] == "1"
    var recordProfile = [UInt64](repeating: 0, count: RecordPart.allCases.count)
    var recordProfileCounts = [Int](repeating: 0, count: RecordPart.allCases.count)

    var feedbackCopies: [String: VKTexture] = [:]
    var textureOverride: [MetalHandle: UInt64] = [:]

    var checkpointRecords: [CheckpointRecord] = []
    var badBaseInstanceLogs = 0
    var probe: PassProbe?
    var probesStarted = 0
    var lastProbeAt: UInt64 = 0
    var lastSkipLine = 0
    var releasedBufferRanges: [(UInt64, UInt64, UInt64)] = []
    var nextCheckpointID: UInt32 = 1
    var deviceLossReported = false

    var held: [HeldKey: [HeldItem]] = [:]
    var heldSince: [HeldKey: UInt64] = [:]
    var heldReported: [HeldKey: UInt64] = [:]
    var heldGraveyard: [() -> Void] = []
    var heldThread: Thread?

    struct TranslationKey: Hashable {
        var hash: UInt64, count: Int, linked: UInt64, linkedCount: Int
    }

    public init(translator: ShaderTranslator? = nil, options: Options = Options()) {
        self.options = options
        self.translator = translator ?? AircProcessTranslator.locate().map {
            AircTranslatorPool(executable: $0, count: options.translatorProcesses)
        }
        compileQueue.maxConcurrentOperationCount = max(options.compileThreads, 1)
        compileQueue.name = "swiftcode-vulkan-pipelines"
        ctx = .allocate(capacity: 1)
        ctx.initialize(to: yvk_context())
        var opts = yvk_context_options(maxSampledImages: options.maxSampledImages, maxSamplers: options.maxSamplers,
                                       maxStorageImages: options.maxStorageImages, validation: options.validation ? 1 : 0,
                                       queues: 1, second: 0)
        var err = [CChar](repeating: 0, count: 512)
        let r = yvk_context_create(ctx, &opts, &err, err.count)
        fn = yvk_fns().pointee
        if r != 0 {
            isAvailable = false
            unavailableReason = cString(err)
            deviceName = ""
            textureIndices = IndexAllocator(capacity: 0)
            samplerIndices = IndexAllocator(capacity: 0)
            return
        }
        deviceName = withUnsafeBytes(of: ctx.pointee.properties.deviceName) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        textureIndices = IndexAllocator(capacity: min(ctx.pointee.heapSampledImages, ctx.pointee.heapStorageImages))
        samplerIndices = IndexAllocator(capacity: ctx.pointee.heapSamplers)
        timeline = yvk_timeline_create(ctx, 0)
        isAvailable = timeline != nil
        unavailableReason = timeline == nil ? "timeline semaphore creation failed" : nil
        guard isAvailable else { return }
        do {
            try createDummies()
        } catch {
            log("dummy resources: \(error)")
        }
        let thread = Thread { [unowned self] in self.completionLoop() }
        thread.name = "swiftcode-vulkan-completion"
        completionThread = thread
        thread.start()
        loadPipelineCache()
        prepareHangInjection()
        if let path = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_TRACE"], !path.isEmpty {
            frameTrace = FrameTrace(path: path, ctx: ctx, fn: fn)
            log(frameTrace == nil ? "frame trace: cannot write \(path) or no timestamp queries" : "frame trace: \(path)")
        }
        if ProcessInfo.processInfo.environment["SWIFTCODE_AIRC_PRESTART"] != "0" {
            (self.translator as? AircTranslatorPool)?.prestart()
        }
    }

    public func shutdown() {
        cond.lock()
        let first = running
        cond.unlock()
        guard first else { return }
        if isAvailable {
            compileQueue.waitUntilAllOperationsAreFinished()
            cacheTimer?.cancel()
            savePipelineCache()
            if verbose && usesPipelineLibraries { log("pipeline libraries: \(pipelineLibraryStatistics.summary)") }
        }
        let grace = UInt64(max(options.shutdownGrace, 0) * 1e9)
        cond.lock()
        guard running else { cond.unlock(); return }
        running = false
        let now = DispatchTime.now().uptimeNanoseconds
        shutdownDeadline = now &+ grace
        cond.broadcast()
        cond.unlock()
        guard isAvailable else {
            yvk_context_destroy(ctx)
            return
        }
        let threadsDeadline = now &+ grace &+ 5_000_000_000
        var threadsDone = false
        while true {
            threadsDone = threadsStopped
            if threadsDone || DispatchTime.now().uptimeNanoseconds >= threadsDeadline { break }
            usleep(1000)
        }
        cond.lock()
        let abandoned = abandonedAtShutdown
        cond.unlock()
        guard threadsDone, !abandoned else {
            log("shutdown: " + (threadsDone ? "GPU work abandoned" : "backend threads still running")
                + "; the device is left to the driver's exit teardown")
            return
        }
        _ = fn.vkDeviceWaitIdle!(ctx.pointee.device)
        destroyEverything()
        destroyKicker()
        yvk_context_destroy(ctx)
    }

    var threadsStopped: Bool {
        cond.lock()
        defer { cond.unlock() }
        return completionThread == nil && heldThread == nil
    }

    public var abandonedWorkAtShutdown: Bool {
        cond.lock()
        defer { cond.unlock() }
        return abandonedAtShutdown
    }

    deinit {
        shutdown()
        ctx.deallocate()
    }

    var skipDraws: Bool {
        options.recordFast ? Self.environmentSkipDraws : ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_SKIP_DRAWS"] != nil
    }
    static let environmentSkipDraws = ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_SKIP_DRAWS"] != nil

    var verbose: Bool { Self.environmentVerbose }
    static let environmentVerbose = ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_LOG"] != nil
    static let environmentDumpFunctions = ProcessInfo.processInfo.environment["SWIFTCODE_VULKAN_DUMP_FUNCTIONS"]

    func log(_ message: String) {
        options.log?("[vulkan] " + message)
    }

    var device: VkDevice? { ctx.pointee.device }

    public func limits() -> MetalLimits {
        guard isAvailable else { return MetalLimits() }
        cond.lock()
        let l = ctx.pointee.properties.limits
        cond.unlock()
        let maxInv = UInt64(min(l.maxComputeWorkGroupInvocations, 1024))
        return MetalLimits(maxThreadsPerThreadgroup: (min(UInt64(l.maxComputeWorkGroupSize.0), maxInv),
                                                      min(UInt64(l.maxComputeWorkGroupSize.1), maxInv),
                                                      min(UInt64(l.maxComputeWorkGroupSize.2), maxInv)),
                           maxThreadgroupMemoryLength: UInt64(min(l.maxComputeSharedMemorySize, 32768)))
    }

    public var subgroupSize: Int { Int(ctx.pointee.subgroupSize) }

    public func vulkanFormat(forMetal metal: UInt32) -> VulkanPixelFormat? {
        cond.lock(); defer { cond.unlock() }
        return resolveFormat(metal)
    }

    func resolveFormat(_ metal: UInt32) -> VulkanPixelFormat? {
        if let cached = formatCache[metal] { return cached }
        var result: VulkanPixelFormat?
        if var f = metalPixelFormatTable(metal) {
            let usable = { (f: VulkanPixelFormat) -> Bool in
                let feats = yvk_format_features(self.ctx, f.format)
                if f.isDepth || f.isStencil { return feats & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue != 0 }
                return feats & (VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT.rawValue | VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT.rawValue) != 0
            }
            if metal == 1 && (!(ctx.pointee.features.formatA8 != 0) || !usable(f)) {
                f.format = VK_FORMAT_R8_UNORM
                f.swizzle = VkComponentMapping(r: VK_COMPONENT_SWIZZLE_ZERO, g: VK_COMPONENT_SWIZZLE_ZERO,
                                               b: VK_COMPONENT_SWIZZLE_ZERO, a: VK_COMPONENT_SWIZZLE_R)
                f.approximate = true
            }
            if !usable(f) && f.isStencil {
                let combined = VK_IMAGE_ASPECT_DEPTH_BIT.rawValue | VK_IMAGE_ASPECT_STENCIL_BIT.rawValue
                for alt in [VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT_S8_UINT] where alt != f.format {
                    var g = f
                    g.format = alt
                    g.aspect = combined
                    if metal == 253 || metal == 261 || metal == 262 { g.viewAspect = VK_IMAGE_ASPECT_STENCIL_BIT.rawValue }
                    if usable(g) { f = g; break }
                }
            }
            if usable(f) { result = f }
        }
        formatCache[metal] = result
        return result
    }

    public func createBuffer(_ handle: MetalHandle, length: Int, storage: MetalStorageMode, guestMemory: GuestSharedRegion?) throws {
        guard isAvailable else { throw VulkanBackendError("no GPU") }
        cond.lock(); defer { cond.unlock() }
        let allocation: VKAllocation
        let offset: Int
        if let g = guestMemory {
            (allocation, offset) = try importRegion(g)
        } else {
            var b = yvk_buffer()
            var err = [CChar](repeating: 0, count: 256)
            let kind = storage == .private || storage == .memoryless ? YVK_MEMORY_DEVICE : YVK_MEMORY_HOST
            guard yvk_buffer_create(ctx, VkDeviceSize(max(length, 4)), kind, nil, &b, &err, err.count) == 0 else {
                throw VulkanBackendError(cString(err))
            }
            allocation = VKAllocation(buffer: b, base: b.mapped, key: nil, owner: nil)
            allocation.kind = kind
            offset = 0
        }
        allocation.references += 1
        if let old = buffers[handle] { releaseBuffer(old) }
        buffers[handle] = VKBuffer(allocation: allocation, offset: offset, length: length, storage: storage)
        statistics.buffers += 1
    }

    func importRegion(_ g: GuestSharedRegion) throws -> (VKAllocation, Int) {
        let align = UInt(ctx.pointee.hostPointerAlignment)
        func range(_ p: UnsafeMutableRawPointer, _ n: Int) -> (UInt, Int) {
            let start = UInt(bitPattern: p) & ~(align - 1)
            let end = (UInt(bitPattern: p) + UInt(max(n, 1)) + align - 1) & ~(align - 1)
            return (start, Int(end - start))
        }
        let regionStart = UInt(bitPattern: g.pointer)
        let whole = range(g.objectPointer, g.objectLength)
        var candidates: [(UInt, Int)] = []
        let slack = UInt(max(0, options.importSlack)) & ~(align - 1)
        if slack > 0, let (w0, wlen) = options.importSlackWindow {
            let lo = max(whole.0 &- slack, (w0 + align - 1) & ~(align - 1))
            let hi = min(whole.0 + UInt(whole.1) + slack, (w0 + wlen) & ~(align - 1))
            if whole.0 >= slack, lo < whole.0 || hi > whole.0 + UInt(whole.1), lo <= whole.0, hi >= whole.0 + UInt(whole.1) {
                candidates.append((lo, Int(hi - lo)))
            }
        }
        candidates.append(whole)
        let tight = range(g.pointer, g.length)
        if tight != whole { candidates.append(tight) }
        var lastError = ""
        for (start, length) in candidates where regionStart >= start && regionStart + UInt(g.length) <= start + UInt(length) {
            let key = AllocationKey(objectID: g.objectID, start: start, length: length)
            if let a = imports[key] { return (a, Int(regionStart - start)) }
            if let a = imports.first(where: { $0.key.objectID == g.objectID && $0.key.start <= regionStart &&
                                               regionStart + UInt(g.length) <= $0.key.start + UInt($0.key.length) })?.value {
                return (a, Int(regionStart - a.key!.start))
            }
            var b = yvk_buffer()
            var err = [CChar](repeating: 0, count: 256)
            let ptr = UnsafeMutableRawPointer(bitPattern: start)
            if yvk_buffer_create(ctx, VkDeviceSize(length), YVK_MEMORY_IMPORT_HOST, ptr, &b, &err, err.count) == 0 {
                let a = VKAllocation(buffer: b, base: ptr, key: key, owner: g.owner)
                a.kind = YVK_MEMORY_IMPORT_HOST
                imports[key] = a
                statistics.imports += 1
                if start < whole.0 || start + UInt(length) > whole.0 + UInt(whole.1) { statistics.slackImports += 1 }
                return (a, Int(regionStart - start))
            }
            lastError = cString(err)
        }
        throw VulkanBackendError("import of guest memory \(g.pointer) (+\(g.length)) failed: \(lastError)")
    }

    func releaseAllocationReference(_ a: VKAllocation) {
        a.references -= 1
        guard a.references <= 0 else { return }
        if let key = a.key { imports[key] = nil }
        deferDestroy { [ctx] in yvk_buffer_destroy(ctx, &a.buffer) }
    }

    func releaseBuffer(_ b: VKBuffer) {
        releaseAllocationReference(b.allocation)
    }

    public func gpuAddress(ofBuffer handle: MetalHandle) -> UInt64? {
        cond.lock(); defer { cond.unlock() }
        return buffers[handle]?.address
    }

    public func createTexture(_ handle: MetalHandle, _ desc: MetalTextureDescriptor, iosurface: IOSurfaceBacking?) throws {
        guard isAvailable else { throw VulkanBackendError("no GPU") }
        cond.lock(); defer { cond.unlock() }
        guard let fmt = resolveFormat(desc.pixelFormat) else {
            throw VulkanBackendError("pixel format \(desc.pixelFormat) is not supported")
        }
        let type = desc.textureType
        let isCube = type == MetalTextureType.typeCube || type == MetalTextureType.typeCubeArray
        let is3D = type == MetalTextureType.type3D
        let is1D = type == MetalTextureType.type1D || type == MetalTextureType.type1DArray
        let isArray = type == MetalTextureType.type1DArray || type == MetalTextureType.type2DArray ||
            type == MetalTextureType.typeCubeArray || type == MetalTextureType.type2DMultisampleArray
        let layers = (isArray ? max(desc.arrayLength, 1) : 1) * (isCube ? 6 : 1)
        let samples = max(desc.sampleCount, 1)
        let width = max(desc.width, 1), height = is1D ? 1 : max(desc.height, 1), depth = is3D ? max(desc.depth, 1) : 1
        let levels = max(desc.mipmapLevelCount, 1)

        let feats = yvk_format_features(ctx, fmt.format)
        var usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue
        if feats & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT.rawValue != 0 { usage |= VK_IMAGE_USAGE_SAMPLED_BIT.rawValue }
        if fmt.isColor && feats & VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT.rawValue != 0 && !fmt.isCompressed {
            usage |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue
        }
        if !fmt.isColor && feats & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue != 0 {
            usage |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue
        }
        let cubeReads = isCube && Self.storageForCubeReads
        let wantsStorage = Self.storageForEveryTexture || desc.usage & MetalTextureUsage.shaderWrite != 0 || desc.usage == 0
            || cubeReads
        var flags: UInt32 = 0
        if wantsStorage && samples == 1 && feats & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT.rawValue != 0 {
            usage |= VK_IMAGE_USAGE_STORAGE_BIT.rawValue
        } else if wantsStorage && samples == 1 && fmt.isColor && !fmt.isCompressed, let sibling = Self.storageSibling(fmt.format),
                  yvk_format_features(ctx, sibling) & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT.rawValue != 0 {
            usage |= VK_IMAGE_USAGE_STORAGE_BIT.rawValue
            flags |= VK_IMAGE_CREATE_EXTENDED_USAGE_BIT.rawValue
        }
        if isCube { flags |= VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT.rawValue }
        if is3D { flags |= VK_IMAGE_CREATE_2D_ARRAY_COMPATIBLE_BIT.rawValue }
        if fmt.isColor && !fmt.isCompressed { flags |= VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT.rawValue }
        var info = yvk_image_info(type: is3D ? VK_IMAGE_TYPE_3D : (is1D ? VK_IMAGE_TYPE_1D : VK_IMAGE_TYPE_2D),
                                  format: fmt.format, width: UInt32(width), height: UInt32(height), depth: UInt32(depth),
                                  mipLevels: UInt32(levels), arrayLayers: UInt32(layers),
                                  samples: VkSampleCountFlagBits(rawValue: UInt32(samples)), usage: usage, flags: flags)
        var img = yvk_image()
        var err = [CChar](repeating: 0, count: 256)
        guard yvk_image_create(ctx, &info, &img, &err, err.count) == 0 else { throw VulkanBackendError(cString(err)) }
        let image = VKImage(image: img, format: fmt, metalFormat: desc.pixelFormat, imageType: info.type, width: width,
                            height: height, depth: depth, levels: levels, layers: layers, samples: samples, usage: usage)
        image.createInfo = info
        if let s = iosurface {
            do {
                let (alloc, offset) = try importRegion(s.region)
                alloc.references += 1
                image.surface = SurfaceLink(allocation: alloc, offset: offset + s.planeOffset, bytesPerRow: s.bytesPerRow,
                                            width: min(s.width, width), height: min(s.height, height), surfaceID: s.surfaceID,
                                            limit: max(0, s.region.length - s.planeOffset), syncState: s.syncState)
                if verbose {
                    log("texture \(handle): IOSurface \(s.surfaceID) \(s.width)x\(s.height) pitch \(s.bytesPerRow) bpe \(s.bytesPerElement) " +
                        "format \(String(s.pixelFormat, radix: 16)) bytes \(s.region.length); Metal format \(desc.pixelFormat) \(width)x\(height)")
                }
            } catch {
                yvk_image_destroy(ctx, &image.image)
                throw error
            }
        }
        try initializeImage(image)
        let tex = VKTexture(image: image, format: fmt, metalFormat: desc.pixelFormat, textureType: type, baseLevel: 0,
                            levelCount: levels, baseLayer: 0, layerCount: layers, swizzle: fmt.swizzle, metalUsage: desc.usage)
        imageReferences[ObjectIdentifier(image)] = 1
        makeShaderViews(tex, handle: handle)
        if let old = textures[handle] { releaseTexture(old) }
        textures[handle] = tex
        statistics.textures += 1
        depthTapNoteTexture(tex)
    }

    public func createTextureView(_ handle: MetalHandle, parent: MetalHandle, _ desc: MetalTextureViewDescriptor) throws {
        guard isAvailable else { throw VulkanBackendError("no GPU") }
        cond.lock(); defer { cond.unlock() }
        guard let p = textures[parent] else { throw VulkanBackendError("texture view of unknown texture \(parent)") }
        guard let fmt = resolveFormat(desc.pixelFormat == 0 ? p.metalFormat : desc.pixelFormat) else {
            throw VulkanBackendError("pixel format \(desc.pixelFormat) is not supported")
        }
        let levels = desc.levels ?? 0..<p.levelCount
        let slices = desc.slices ?? 0..<p.layerCount
        let type = desc.textureType ?? p.textureType
        var outer = identitySwizzle
        if let s = desc.swizzle, s.count == 4 {
            outer = VkComponentMapping(r: vkSwizzle(s[0]), g: vkSwizzle(s[1]), b: vkSwizzle(s[2]), a: vkSwizzle(s[3]))
        }
        let tex = VKTexture(image: p.image, format: fmt, metalFormat: desc.pixelFormat == 0 ? p.metalFormat : desc.pixelFormat,
                            textureType: type, baseLevel: p.baseLevel + levels.lowerBound, levelCount: max(levels.count, 1),
                            baseLayer: p.baseLayer + slices.lowerBound, layerCount: max(slices.count, 1),
                            swizzle: composeSwizzle(outer, over: fmt.swizzle), metalUsage: p.metalUsage)
        imageReferences[ObjectIdentifier(p.image), default: 0] += 1
        makeShaderViews(tex, handle: handle)
        if let old = textures[handle] { releaseTexture(old) }
        textures[handle] = tex
    }

    func initializeImage(_ image: VKImage) throws {
        let rec = try setupRecording()
        yvk_cmd_image_layout(rec.cb, image.vkImage, image.format.aspect, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL)
        rec.empty = false
        image.initialized = true
    }

    func viewType(for tex: VKTexture) -> VkImageViewType {
        switch tex.textureType {
        case MetalTextureType.type1D: return tex.layerCount > 1 ? VK_IMAGE_VIEW_TYPE_1D_ARRAY : VK_IMAGE_VIEW_TYPE_1D
        case MetalTextureType.type1DArray: return VK_IMAGE_VIEW_TYPE_1D_ARRAY
        case MetalTextureType.type2DArray, MetalTextureType.type2DMultisampleArray: return VK_IMAGE_VIEW_TYPE_2D_ARRAY
        case MetalTextureType.typeCube: return VK_IMAGE_VIEW_TYPE_CUBE
        case MetalTextureType.typeCubeArray: return VK_IMAGE_VIEW_TYPE_CUBE_ARRAY
        case MetalTextureType.type3D: return VK_IMAGE_VIEW_TYPE_3D
        default: return VK_IMAGE_VIEW_TYPE_2D
        }
    }

    func makeShaderViews(_ tex: VKTexture, handle: MetalHandle? = nil, keepSlot: Bool = false) {
        let kept: (index: UInt32, count: UInt32)? = keepSlot && tex.heapIndex != 0 ? (tex.heapIndex, max(tex.heapCount, 1)) : nil
        let reserved = kept ?? handle.flatMap { reservedTextureSlots.removeValue(forKey: $0) }
        let image = tex.image
        guard tex.textureType != MetalTextureType.typeTextureBuffer else { return }
        var err = [CChar](repeating: 0, count: 256)
        if image.usage & VK_IMAGE_USAGE_SAMPLED_BIT.rawValue != 0,
           yvk_format_features(ctx, tex.format.format) & VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT.rawValue != 0 {
            var vi = yvk_view_info(image: image.vkImage, viewType: viewType(for: tex), format: tex.format.format,
                                   aspect: tex.format.viewAspect, baseLevel: UInt32(tex.baseLevel),
                                   levelCount: UInt32(tex.levelCount), baseLayer: UInt32(tex.baseLayer),
                                   layerCount: UInt32(tex.layerCount), components: tex.swizzle,
                                   usage: VK_IMAGE_USAGE_SAMPLED_BIT.rawValue)
            tex.shaderView = yvk_view_create(ctx, &vi, &err, err.count)
            if tex.shaderView == nil { log("sampled view: \(cString(err))") }
        }
        var storageFormat = tex.format.format
        if image.usage & VK_IMAGE_USAGE_STORAGE_BIT.rawValue != 0, Self.srgbStorageViews,
           yvk_format_features(ctx, storageFormat) & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT.rawValue == 0,
           let sibling = Self.storageSibling(storageFormat),
           yvk_format_features(ctx, sibling) & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT.rawValue != 0 {
            storageFormat = sibling
            tex.srgbStorage = true
        }
        if image.usage & VK_IMAGE_USAGE_STORAGE_BIT.rawValue != 0, isIdentitySwizzle(tex.swizzle),
           yvk_format_features(ctx, storageFormat) & VK_FORMAT_FEATURE_STORAGE_IMAGE_BIT.rawValue != 0 {
            var vi = yvk_view_info(image: image.vkImage, viewType: viewType(for: tex), format: storageFormat,
                                   aspect: tex.format.viewAspect, baseLevel: UInt32(tex.baseLevel),
                                   levelCount: UInt32(tex.levelCount), baseLayer: UInt32(tex.baseLayer),
                                   layerCount: UInt32(tex.layerCount), components: identitySwizzle,
                                   usage: VK_IMAGE_USAGE_STORAGE_BIT.rawValue)
            tex.storageView = yvk_view_create(ctx, &vi, &err, err.count)
        }
        if tex.storageView == nil { tex.srgbStorage = false }
        guard tex.shaderView != nil || tex.storageView != nil else {
            if let r = reserved {
                if kept != nil {
                    for i in 0..<r.count {
                        yvk_heap_write_sampled(ctx, r.index + i, dummyView)
                        yvk_heap_write_storage(ctx, r.index + i, dummyView)
                    }
                } else {
                    textureIndices.release(r.index, count: r.count)
                }
            }
            return
        }
        let count = tex.storageView != nil && tex.levelCount > 1 ? UInt32(tex.levelCount) : 1
        var owned = count
        var slot: UInt32?
        if let r = reserved {
            if r.count == count || r.count == 1 || kept != nil {
                slot = r.index
                owned = kept != nil ? min(r.count, count) : r.count
            } else {
                textureIndices.release(r.index, count: r.count)
            }
        }
        if slot == nil { slot = textureIndices.allocate(count) }
        if slot == nil && count > 1 { owned = 1; slot = textureIndices.allocate(1) }
        guard let index = slot else { return }
        tex.heapIndex = index
        tex.heapCount = owned
        yvk_heap_write_sampled(ctx, index, tex.shaderView ?? dummyView)
        yvk_heap_write_storage(ctx, index, tex.storageView ?? dummyView)
        guard tex.heapCount > 1 else { return }
        for level in 1..<Int(tex.heapCount) {
            var vi = yvk_view_info(image: image.vkImage, viewType: viewType(for: tex), format: storageFormat,
                                   aspect: tex.format.viewAspect, baseLevel: UInt32(tex.baseLevel + level), levelCount: 1,
                                   baseLayer: UInt32(tex.baseLayer), layerCount: UInt32(tex.layerCount),
                                   components: identitySwizzle, usage: VK_IMAGE_USAGE_STORAGE_BIT.rawValue)
            let v = yvk_view_create(ctx, &vi, &err, err.count)
            if let v { tex.levelStorageViews.append(v) }
            yvk_heap_write_sampled(ctx, index + UInt32(level), dummyView)
            yvk_heap_write_storage(ctx, index + UInt32(level), v ?? dummyView)
        }
    }

    static func storageSibling(_ format: VkFormat) -> VkFormat? {
        switch format {
        case VK_FORMAT_R8G8B8A8_SRGB: return VK_FORMAT_R8G8B8A8_UNORM
        case VK_FORMAT_B8G8R8A8_SRGB: return VK_FORMAT_B8G8R8A8_UNORM
        case VK_FORMAT_A8B8G8R8_SRGB_PACK32: return VK_FORMAT_A8B8G8R8_UNORM_PACK32
        case VK_FORMAT_R8_SRGB: return VK_FORMAT_R8_UNORM
        case VK_FORMAT_R8G8_SRGB: return VK_FORMAT_R8G8_UNORM
        default: return nil
        }
    }

    static let srgbStorageViews = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_SRGB_STORAGE"] != "0"

    static let storageForEveryTexture = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_STORAGE_USAGE"] == "all"

    static let storageForCubeReads = ProcessInfo.processInfo.environment["SWIFTCODE_GPU_CUBE_STORAGE"] != "0"

    func attachmentView(_ tex: VKTexture, level: Int, slice: Int) -> VkImageView? {
        let key = level << 20 | slice
        if let v = tex.attachmentViews[key] { return v }
        let image = tex.image
        let attachmentUsage = tex.format.isColor ? VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue
            : VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue
        guard image.usage & attachmentUsage != 0 else { return nil }
        var vi = yvk_view_info(image: image.vkImage, viewType: VK_IMAGE_VIEW_TYPE_2D, format: tex.format.format,
                               aspect: tex.format.aspect, baseLevel: UInt32(tex.baseLevel + level), levelCount: 1,
                               baseLayer: UInt32(image.imageType == VK_IMAGE_TYPE_3D ? slice : tex.baseLayer + slice),
                               layerCount: 1, components: identitySwizzle, usage: attachmentUsage)
        var err = [CChar](repeating: 0, count: 256)
        let v = yvk_view_create(ctx, &vi, &err, err.count)
        if v == nil { log("attachment view: \(cString(err))") }
        tex.attachmentViews[key] = v
        return v
    }

    func releaseTexture(_ tex: VKTexture) {
        let views = [tex.shaderView, tex.storageView].compactMap { $0 } + Array(tex.attachmentViews.values.compactMap { $0 })
            + tex.levelStorageViews
        let index = tex.heapIndex, count = tex.heapCount
        let image = tex.image
        let id = ObjectIdentifier(image)
        imageReferences[id, default: 1] -= 1
        let destroyImage = imageReferences[id]! <= 0
        if destroyImage {
            imageReferences[id] = nil
            if let s = image.surface { releaseAllocationReference(s.allocation) }
        }
        deferDestroy { [ctx, fn, weak self] in
            if index != 0, let self {
                for i in 0..<count {
                    yvk_heap_write_sampled(ctx, index + i, self.dummyView)
                    yvk_heap_write_storage(ctx, index + i, self.dummyView)
                }
                self.textureIndices.release(index, count: count)
            }
            for v in views { fn.vkDestroyImageView!(ctx.pointee.device, v, nil) }
            if destroyImage { yvk_image_destroy(ctx, &image.image) }
        }
    }

    public func createSampler(_ handle: MetalHandle, _ desc: MetalSamplerDescriptor) throws {
        guard isAvailable else { throw VulkanBackendError("no GPU") }
        cond.lock(); defer { cond.unlock() }
        samplers[handle] = try sampler(for: SamplerKey(desc), reserved: reservedSamplerSlots.removeValue(forKey: handle))
    }

    func sampler(for key: SamplerKey, reserved: UInt32? = nil) throws -> VKSampler {
        if let s = samplerCache[key] { return s }
        let index: UInt32
        if let r = reserved, reservedSamplerIndices.remove(r) != nil {
            index = r
        } else if let i = samplerIndices.allocate() {
            index = i
        } else {
            throw VulkanBackendError("sampler heap is full")
        }
        var info = samplerInfo(key)
        var err = [CChar](repeating: 0, count: 256)
        guard let s = yvk_sampler_create(ctx, &info, &err, err.count) else {
            samplerIndices.release(index)
            throw VulkanBackendError(cString(err))
        }
        yvk_heap_write_sampler(ctx, index, s)
        let v = VKSampler(sampler: s, heapIndex: index, key: key)
        samplerCache[key] = v
        statistics.samplers += 1
        return v
    }

    func samplerInfo(_ k: SamplerKey) -> yvk_sampler_info {
        let mirror = ctx.pointee.features.samplerMirrorClampToEdge != 0
        var i = yvk_sampler_info()
        i.magFilter = k.magFilter == 1 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST
        i.minFilter = k.minFilter == 1 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST
        i.mipmapMode = k.mipFilter == 2 ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST
        i.addressU = vkAddressMode(k.s, mirrorClampSupported: mirror)
        i.addressV = vkAddressMode(k.t, mirrorClampSupported: mirror)
        i.addressW = vkAddressMode(k.r, mirrorClampSupported: mirror)
        i.minLod = max(k.lodMin, 0)
        i.maxLod = min(k.lodMax, 1000)
        if k.mipFilter == 0 {
            i.minLod = 0
            i.maxLod = 0.25
        }
        i.borderColor = [k.s, k.t, k.r].contains(5) ? vkBorderColor(k.border) : VK_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK
        i.compareEnable = k.compare != 0 ? 1 : 0
        i.compareOp = vkCompare(k.compare)
        i.maxAnisotropy = Float(max(k.anisotropy, 1))
        i.anisotropyEnable = k.anisotropy > 1 ? 1 : 0
        if !k.normalized {
            i.unnormalizedCoordinates = 1
            i.minFilter = i.magFilter
            i.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
            i.minLod = 0
            i.maxLod = 0
            i.anisotropyEnable = 0
            i.compareEnable = 0
            for p in [\yvk_sampler_info.addressU, \yvk_sampler_info.addressV, \yvk_sampler_info.addressW]
            where i[keyPath: p] != VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER {
                i[keyPath: p] = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            }
        }
        return i
    }

    public func gpuResourceID(ofSampler handle: MetalHandle) -> UInt64? {
        cond.lock(); defer { cond.unlock() }
        return samplers[handle].map { UInt64($0.heapIndex) }
    }

    public func gpuResourceID(ofTexture handle: MetalHandle) -> UInt64? {
        cond.lock(); defer { cond.unlock() }
        return textures[handle].map { $0.shaderHandle }
    }

    public func heapSlots(ofTexture handle: MetalHandle) -> (index: UInt32, count: UInt32)? {
        cond.lock(); defer { cond.unlock() }
        guard let t = textures[handle], t.heapIndex != 0 else { return nil }
        return (t.heapIndex, max(t.heapCount, 1))
    }

    public func reserveHeapSlots(textures: [MetalHandle: (index: UInt32, count: UInt32)], samplers: [MetalHandle: UInt32]) {
        guard isAvailable else { return }
        cond.lock(); defer { cond.unlock() }
        for run in reservedTextureSlots.values { textureIndices.release(run.index, count: run.count) }
        for index in reservedSamplerIndices { samplerIndices.release(index) }
        reservedTextureSlots = [:]
        reservedSamplerSlots = [:]
        reservedSamplerIndices = []
        for (h, run) in textures.sorted(by: { $0.value.index < $1.value.index })
        where textureIndices.claim(run.index, count: run.count) {
            reservedTextureSlots[h] = run
        }
        for index in Set(samplers.values).sorted() where samplerIndices.claim(index) {
            reservedSamplerIndices.insert(index)
        }
        for (h, index) in samplers where reservedSamplerIndices.contains(index) { reservedSamplerSlots[h] = index }
    }

    public func writeBuffer(_ handle: MetalHandle, offset: Int, _ bytes: [UInt8]) -> Bool {
        cond.lock(); defer { cond.unlock() }
        guard let b = buffers[handle], let p = b.hostPointer, offset >= 0, offset + bytes.count <= b.length else { return false }
        bytes.withUnsafeBytes { (p + offset).copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
        return true
    }

    public func createDepthStencilState(_ handle: MetalHandle, _ desc: MetalDepthStencilDescriptor) throws {
        cond.lock(); defer { cond.unlock() }
        depthStencilStates[handle] = desc
    }

    public func createFunction(_ handle: MetalHandle, metallib: [UInt8]) throws {
        cond.lock(); defer { cond.unlock() }
        functions[handle] = VKFunction(metallib: metallib)
        if let dir = Self.environmentDumpFunctions {
            let path = "\(dir)/function-\(handle.raw)-\(String(fnv1a64(metallib), radix: 16)).metallib"
            FileManager.default.createFile(atPath: path, contents: Data(metallib))
        }
    }

    public func createEvent(_ handle: MetalHandle) throws {
        guard isAvailable else { return }
        cond.lock(); defer { cond.unlock() }
        events[handle] = VKEvent(semaphore: yvk_timeline_create(ctx, 0))
    }

    public func createEventAlias(_ handle: MetalHandle, of original: MetalHandle) throws {
        guard isAvailable else { return }
        cond.lock(); defer { cond.unlock() }
        events[handle] = events[original] ?? VKEvent(semaphore: yvk_timeline_create(ctx, 0))
    }

    public func signalEvent(_ handle: MetalHandle, value: UInt64) {
        cond.lock(); defer { cond.unlock() }
        guard let e = events[handle], let s = e.semaphore else { return }
        if value > yvk_timeline_value(ctx, s) && value > e.highest {
            _ = yvk_timeline_signal(ctx, s, value)
            e.highest = value
        }
    }

    public func eventValue(_ handle: MetalHandle) -> UInt64? {
        cond.lock(); defer { cond.unlock() }
        guard let e = events[handle], let s = e.semaphore else { return nil }
        return yvk_timeline_value(ctx, s)
    }

    public func release(_ handle: MetalHandle) {
        cond.lock(); defer { cond.unlock() }
        if let b = buffers.removeValue(forKey: handle) {
            releasedBufferRanges.append((b.address, b.address + UInt64(b.length), handle.raw))
            if releasedBufferRanges.count > 16384 { releasedBufferRanges.removeFirst(4096) }
            releaseBuffer(b)
            return
        }
        if let t = textures.removeValue(forKey: handle) { releaseTexture(t); return }
        if samplers.removeValue(forKey: handle) != nil { return }
        if depthStencilStates.removeValue(forKey: handle) != nil { return }
        if functions.removeValue(forKey: handle) != nil { return }
        if let p = renderPipelines.removeValue(forKey: handle) { releaseRenderPipeline(p); return }
        if let p = computePipelines.removeValue(forKey: handle) { releaseComputePipeline(p); return }
        if let e = events.removeValue(forKey: handle), let s = e.semaphore,
           !events.values.contains(where: { $0 === e }) {
            deferDestroy { [ctx, fn] in fn.vkDestroySemaphore!(ctx.pointee.device, s, nil) }
        }
    }

    func deferDestroy(_ action: @escaping () -> Void) {
        if !held.isEmpty {
            heldGraveyard.append(action)
            return
        }
        let serial = (setup?.empty == false) ? lastSubmitted + 1 : lastSubmitted
        if serial <= completedSerial {
            action()
        } else {
            graveyard.append((serial, action))
        }
    }

    func createDummies() throws {
        cond.lock(); defer { cond.unlock() }
        try createDummiesLocked()
    }

    func createDummiesLocked() throws {
        var info = yvk_image_info(type: VK_IMAGE_TYPE_2D, format: VK_FORMAT_R8G8B8A8_UNORM, width: 1, height: 1, depth: 1,
                                  mipLevels: 1, arrayLayers: 1, samples: VK_SAMPLE_COUNT_1_BIT,
                                  usage: VK_IMAGE_USAGE_SAMPLED_BIT.rawValue | VK_IMAGE_USAGE_STORAGE_BIT.rawValue |
                                      VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue, flags: 0)
        var img = yvk_image()
        var err = [CChar](repeating: 0, count: 256)
        guard yvk_image_create(ctx, &info, &img, &err, err.count) == 0 else { throw VulkanBackendError(cString(err)) }
        let image = VKImage(image: img, format: metalPixelFormatTable(70)!, metalFormat: 70, imageType: VK_IMAGE_TYPE_2D,
                            width: 1, height: 1, depth: 1, levels: 1, layers: 1, samples: 1, usage: info.usage)
        try initializeImage(image)
        let rec = try setupRecording()
        var clear = VkClearColorValue(float32: (0, 0, 0, 0))
        var range = VkImageSubresourceRange(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, baseMipLevel: 0, levelCount: 1,
                                            baseArrayLayer: 0, layerCount: 1)
        fn.vkCmdClearColorImage!(rec.cb, image.vkImage, VK_IMAGE_LAYOUT_GENERAL, &clear, 1, &range)
        dummyImage = image
        var vi = yvk_view_info(image: image.vkImage, viewType: VK_IMAGE_VIEW_TYPE_2D, format: VK_FORMAT_R8G8B8A8_UNORM,
                               aspect: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, baseLevel: 0, levelCount: 1, baseLayer: 0,
                               layerCount: 1, components: identitySwizzle, usage: 0)
        dummyView = yvk_view_create(ctx, &vi, &err, err.count)
        if let v = dummyView {
            yvk_heap_write_sampled(ctx, 0, v)
            yvk_heap_write_storage(ctx, 0, v)
        }
        if yvk_buffer_create(ctx, 65536, YVK_MEMORY_HOST, nil, &dummyBuffer, &err, err.count) == 0, let p = dummyBuffer.mapped {
            p.initializeMemory(as: UInt8.self, repeating: 0, count: 65536)
        }
        var si = samplerInfo(SamplerKey(MetalSamplerDescriptor()))
        defaultSampler = yvk_sampler_create(ctx, &si, &err, err.count)
        if let s = defaultSampler { yvk_heap_write_sampler(ctx, 0, s) }
    }

    func destroyEverything() {
        cond.lock(); defer { cond.unlock() }
        for b in buffers.values { releaseBuffer(b) }
        buffers.removeAll()
        for t in textures.values { releaseTexture(t) }
        textures.removeAll()
        for p in renderPipelines.values { releaseRenderPipeline(p) }
        renderPipelines.removeAll()
        for p in computePipelines.values { releaseComputePipeline(p) }
        computePipelines.removeAll()
        for e in events.values { if let s = e.semaphore { fn.vkDestroySemaphore!(device, s, nil) } }
        events.removeAll()
        for g in graveyard { g.action() }
        graveyard.removeAll()
        for p in libraries.all() { fn.vkDestroyPipeline!(device, p, nil) }
        for t in feedbackCopies.values { releaseTexture(t) }
        feedbackCopies.removeAll()
        for g in graveyard { g.action() }
        graveyard.removeAll()
        for s in samplerCache.values { if let v = s.sampler { fn.vkDestroySampler!(device, v, nil) } }
        samplerCache.removeAll()
        if let s = defaultSampler { fn.vkDestroySampler!(device, s, nil) }
        if let v = dummyView { fn.vkDestroyImageView!(device, v, nil) }
        frameTrace?.destroy(device, fn)
        frameTrace = nil
        if let d = dummyImage { yvk_image_destroy(ctx, &d.image) }
        yvk_buffer_destroy(ctx, &dummyBuffer)
        for c in freeChunks { yvk_buffer_destroy(ctx, &c.buffer) }
        freeChunks.removeAll()
        for p in freeVisibilityPools { fn.vkDestroyQueryPool!(device, p, nil) }
        freeVisibilityPools.removeAll()
        if let s = setup { for c in s.chunks { yvk_buffer_destroy(ctx, &c.buffer) } }
        setup = nil
        if let t = timeline { fn.vkDestroySemaphore!(device, t, nil) }
        timeline = nil
    }
}

enum RecordPart: Int, CaseIterable {
    case start, surfacesIn, passBegin, drawPrepare, table, renderCommands, passEnd, compute, blit, barriers, surfacesOut, submit, label

    var name: String { "\(self)" }
}

extension VulkanMetalBackend {
    @inline(__always)
    func profiled(_ part: RecordPart, since start: UInt64) {
        guard recordProfiling else { return }
        recordProfile[part.rawValue] &+= DispatchTime.now().uptimeNanoseconds &- start
        recordProfileCounts[part.rawValue] += 1
    }

    @inline(__always)
    func profileClock() -> UInt64 { recordProfiling ? DispatchTime.now().uptimeNanoseconds : 0 }

    var recordProfileSummary: String {
        RecordPart.allCases.map { p in
            String(format: "%@ %.1f ms/%d", p.name, Double(recordProfile[p.rawValue]) / 1e6, recordProfileCounts[p.rawValue])
        }.joined(separator: ", ")
    }
}

public struct VulkanBackendStatistics: Sendable {
    public var buffers = 0, textures = 0, samplers = 0, imports = 0
    public var clientHangs = 0, revokedClients = 0, revokedRefusals = 0, exemptFromRevocation = 0
    public var renderPipelines = 0, computePipelines = 0
    public var submissions = 0, draws = 0, dispatches = 0, blits = 0, skipped = 0
    public var surfaceUploads = 0, surfaceDownloads = 0
    public var completedCommandBuffers = 0
    public var latencyTotalNs: UInt64 = 0, latencyMaxNs: UInt64 = 0
    public var translations = TimeCounter(), translationHits = 0
    public var renderCompiles = TimeCounter(), computeCompiles = TimeCounter()
    public var pipelineWaits = TimeCounter()
    public var recording = TimeCounter()
    public var surfaceBytesUp = 0, surfaceBytesDown = 0
    public var surfaceUploadsSkipped = 0, surfaceBytesDownFull = 0
    public var lateWakeups = 0
    public var earlyScheduled = 0
    public var surfaceWriteWaits = TimeCounter()
    public var surfaceWriteWaitTimeouts = 0
    public var laneIsolatedDispatches = 0
    public var unboundBufferReads = 0
    public var mixedSizePasses = 0
    public var slackImports = 0
    public var feedbackSnapshots = 0
    public var feedbackTexels = 0
    public var visibilityPasses = 0, visibilityQueries = 0, visibilitySharedSlots = 0
    public var latencyBuckets = [Int](repeating: 0, count: 7)
    public static let latencyBucketLimitsNs: [UInt64] = [1, 2, 4, 8, 16, 33].map { $0 * 1_000_000 }
}

public struct TimeCounter: Sendable, CustomStringConvertible {
    public var count = 0
    public var totalNs: UInt64 = 0, maxNs: UInt64 = 0
    public init() {}
    public mutating func add(_ ns: UInt64) {
        count += 1
        totalNs &+= ns
        maxNs = max(maxNs, ns)
    }
    public var description: String {
        String(format: "%d (%.1f ms, max %.1f ms)", count, Double(totalNs) / 1e6, Double(maxNs) / 1e6)
    }
}

extension VulkanMetalBackend {
    public var stats: VulkanBackendStatistics {
        cond.lock(); defer { cond.unlock() }
        return statistics
    }
}

extension VulkanMetalBackend {
    public func diagnosticSummary() -> String? {
        guard isAvailable else { return nil }
        cond.lock()
        let s = statistics
        let queued = pending.count
        let serials = "\(completedSerial)/\(lastSubmitted)"
        let brokenRender = renderPipelines.values.filter { $0.broken || !$0.failed.isEmpty }.count
        let brokenCompute = computePipelines.values.filter { $0.broken || !$0.failed.isEmpty }.count
        let lost = deviceLost
        let resets = deviceResets
        let badIndexReleases = textureIndices.badReleases + samplerIndices.badReleases
        let skips = skipLines.sorted { $0.key < $1.key }.map { "L\($0.key)×\($0.value)" }.joined(separator: " ")
        cond.unlock()
        return "serials \(serials), \(queued) pending, compile queue \(compileQueue.operationCount), "
            + "\(s.renderPipelines) render / \(s.computePipelines) compute pipelines (broken \(brokenRender) / \(brokenCompute)), "
            + "\(s.submissions) submissions, \(s.draws) draws, \(s.dispatches) dispatches, \(s.blits) blits, \(s.skipped) skipped, "
            + "surface up/down \(s.surfaceUploads)/\(s.surfaceDownloads), \(s.textures) textures, \(s.buffers) buffers, \(s.imports) imports (\(s.slackImports) with slack)"
            + (s.completedCommandBuffers == 0 ? "" : String(format: ", latency avg %.2f ms max %.1f ms",
                                                              Double(s.latencyTotalNs) / Double(s.completedCommandBuffers) / 1e6,
                                                              Double(s.latencyMaxNs) / 1e6))
            + (skips.isEmpty ? "" : " (skips by replay line: \(skips))")
            + (lost ? ", DEVICE LOST" : "")
            + (resets > 0 ? ", \(resets) device resets" : "")
            + (s.clientHangs > 0 ? ", \(s.clientHangs) client GPU hangs, \(s.revokedClients) clients revoked (\(s.revokedRefusals) refused)" : "")
            + (badIndexReleases > 0 ? ", \(badIndexReleases) heap indices released twice" : "")
            + "; translations \(s.translations) + \(s.translationHits) cached, render compiles \(s.renderCompiles), "
            + "compute variants \(s.computeCompiles), pipeline waits \(s.pipelineWaits), recording \(s.recording), "
            + String(format: "surface MB up/down %.0f/%.0f (whole surfaces would be down %.0f; %d copy-ins skipped)",
                     Double(s.surfaceBytesUp) / 1e6, Double(s.surfaceBytesDown) / 1e6, Double(s.surfaceBytesDownFull) / 1e6,
                     s.surfaceUploadsSkipped) + ", \(s.lateWakeups) late wake-ups, \(s.earlyScheduled) scheduled at submission, surface write waits \(s.surfaceWriteWaits) (\(s.surfaceWriteWaitTimeouts) timed out)"
            + ", \(s.laneIsolatedDispatches) lane-isolated dispatches, \(s.unboundBufferReads) tables with unbound buffers read, \(s.mixedSizePasses) passes of mixed sizes, \(s.feedbackSnapshots) feedback copies (\(s.feedbackTexels / 1_000_000) Mtexels)"
            + ", latency ms <1/<2/<4/<8/<16/<33/more " + s.latencyBuckets.map(String.init).joined(separator: "/")
            + (usesPipelineLibraries ? "; libraries: " + pipelineLibraryStatistics.summary : "")
            + (recordProfiling ? "; recording parts: " + lockedRecordProfileSummary() : "")
    }

    func lockedRecordProfileSummary() -> String {
        cond.lock(); defer { cond.unlock() }
        return recordProfileSummary
    }

    func noteSkip(_ line: Int = #line) {
        statistics.skipped += 1
        skipLines[line, default: 0] += 1
        lastSkipLine = line
    }
}
