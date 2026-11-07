import CVulkan
import Foundation
import SwiftCodeMetalHost

final class VKAllocation {
    var buffer: yvk_buffer
    var base: UnsafeMutableRawPointer?
    var kind: yvk_memory_kind = YVK_MEMORY_HOST
    let key: AllocationKey?
    var references = 0
    let owner: AnyObject?

    init(buffer: yvk_buffer, base: UnsafeMutableRawPointer?, key: AllocationKey?, owner: AnyObject?) {
        self.buffer = buffer
        self.base = base
        self.key = key
        self.owner = owner
    }
}

struct AllocationKey: Hashable {
    var objectID: UInt64
    var start: UInt
    var length: Int
}

final class VKBuffer {
    let allocation: VKAllocation
    let offset: Int
    let length: Int
    let storage: MetalStorageMode

    init(allocation: VKAllocation, offset: Int, length: Int, storage: MetalStorageMode) {
        self.allocation = allocation
        self.offset = offset
        self.length = length
        self.storage = storage
    }

    var vkBuffer: VkBuffer? { allocation.buffer.buffer }
    var address: UInt64 { allocation.buffer.address + UInt64(offset) }
    var hostPointer: UnsafeMutableRawPointer? { allocation.buffer.mapped.map { $0 + offset } }
}

struct SurfaceLink {
    let allocation: VKAllocation
    let offset: Int
    let bytesPerRow: Int
    let width: Int
    let height: Int
    let surfaceID: UInt32
    let limit: Int
    var syncState: (@Sendable () -> (seed: UInt32, locked: Bool)?)?
    var syncKey: SurfaceSyncKey { SurfaceSyncKey(surfaceID: surfaceID, offset: offset) }
}

struct SurfaceSyncKey: Hashable {
    var surfaceID: UInt32
    var offset: Int
}

struct SurfaceDamage {
    var isFull = false
    var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min
    static let full = SurfaceDamage(isFull: true)

    init() {}
    init(isFull: Bool) { self.isFull = isFull }
    init(x: Int, y: Int, width: Int, height: Int) {
        if width > 0 && height > 0 { x0 = x; y0 = y; x1 = x + width; y1 = y + height }
    }

    var isEmpty: Bool { !isFull && (x1 <= x0 || y1 <= y0) }

    mutating func add(_ d: SurfaceDamage) {
        if isFull || d.isEmpty { return }
        if d.isFull { self = .full; return }
        x0 = min(x0, d.x0); y0 = min(y0, d.y0); x1 = max(x1, d.x1); y1 = max(y1, d.y1)
    }
}

final class VKImage {
    var image: yvk_image
    let format: VulkanPixelFormat
    let metalFormat: UInt32
    let imageType: VkImageType
    let width: Int, height: Int, depth: Int
    let levels: Int, layers: Int
    let samples: Int
    let usage: VkImageUsageFlags
    var surface: SurfaceLink?
    var createInfo = yvk_image_info()
    var initialized = false
    var syncedGeneration: UInt64?
    var syncedSeed: UInt32 = 0

    init(image: yvk_image, format: VulkanPixelFormat, metalFormat: UInt32, imageType: VkImageType, width: Int,
         height: Int, depth: Int, levels: Int, layers: Int, samples: Int, usage: VkImageUsageFlags) {
        self.image = image
        self.format = format
        self.metalFormat = metalFormat
        self.imageType = imageType
        self.width = width
        self.height = height
        self.depth = depth
        self.levels = levels
        self.layers = layers
        self.samples = samples
        self.usage = usage
    }

    var vkImage: VkImage? { image.image }

    func levelSize(_ level: Int) -> (Int, Int, Int) {
        (max(1, width >> level), max(1, height >> level), imageType == VK_IMAGE_TYPE_3D ? max(1, depth >> level) : 1)
    }
}

final class VKTexture {
    let image: VKImage
    let format: VulkanPixelFormat
    let metalFormat: UInt32
    let textureType: UInt8
    let baseLevel: Int, levelCount: Int
    let baseLayer: Int, layerCount: Int
    let swizzle: VkComponentMapping
    let metalUsage: UInt16
    var shaderView: VkImageView?
    var storageView: VkImageView?
    var heapIndex: UInt32 = 0
    var heapCount: UInt32 = 1
    var levelStorageViews: [VkImageView] = []
    var srgbStorage = false
    var shaderHandle: UInt64 { UInt64(heapIndex) | (srgbStorage && heapIndex != 0 ? 1 << 32 : 0) }
    var attachmentViews: [Int: VkImageView] = [:]

    init(image: VKImage, format: VulkanPixelFormat, metalFormat: UInt32, textureType: UInt8, baseLevel: Int,
         levelCount: Int, baseLayer: Int, layerCount: Int, swizzle: VkComponentMapping, metalUsage: UInt16) {
        self.image = image
        self.format = format
        self.metalFormat = metalFormat
        self.textureType = textureType
        self.baseLevel = baseLevel
        self.levelCount = levelCount
        self.baseLayer = baseLayer
        self.layerCount = layerCount
        self.swizzle = swizzle
        self.metalUsage = metalUsage
    }

    func levelSize(_ level: Int) -> (Int, Int, Int) { image.levelSize(baseLevel + level) }
}

final class VKSampler {
    var sampler: VkSampler?
    let heapIndex: UInt32
    let key: SamplerKey
    init(sampler: VkSampler?, heapIndex: UInt32, key: SamplerKey) {
        self.sampler = sampler
        self.heapIndex = heapIndex
        self.key = key
    }
}

struct SamplerKey: Hashable {
    var minFilter: UInt8, magFilter: UInt8, mipFilter: UInt8
    var s: UInt8, t: UInt8, r: UInt8
    var border: UInt8, compare: UInt8, anisotropy: UInt8
    var normalized: Bool
    var lodMin: Float, lodMax: Float

    init(_ d: MetalSamplerDescriptor) {
        minFilter = d.minFilter; magFilter = d.magFilter; mipFilter = d.mipFilter
        s = d.sAddressMode; t = d.tAddressMode; r = d.rAddressMode
        border = d.borderColor; compare = d.compareFunction; anisotropy = d.maxAnisotropy
        normalized = d.normalizedCoordinates
        lodMin = d.lodMinClamp; lodMax = d.lodMaxClamp
    }

    init(_ c: ShaderReflection.ConstexprSampler) {
        func address(_ n: String?) -> UInt8 {
            switch n {
            case "mirror_clamp_to_edge": return 1
            case "repeat": return 2
            case "mirrored_repeat": return 3
            case "clamp_to_zero": return 4
            case "clamp_to_border": return 5
            default: return 0
            }
        }
        func filter(_ n: String?) -> UInt8 { n == "linear" || n == "bicubic" ? 1 : 0 }
        func mip(_ n: String?) -> UInt8 { n == "linear" ? 2 : (n == "nearest" ? 1 : 0) }
        func compare(_ n: String?) -> UInt8 {
            ["never": 0, "less": 1, "equal": 2, "less_equal": 3, "greater": 4, "not_equal": 5, "greater_equal": 6,
             "always": 7][n ?? "never"] ?? 0
        }
        func border(_ n: String?) -> UInt8 { n == "opaque_white" ? 2 : (n == "opaque_black" ? 1 : 0) }
        var d = MetalSamplerDescriptor()
        d.minFilter = filter(c.minFilter); d.magFilter = filter(c.magFilter); d.mipFilter = mip(c.mipFilter)
        d.sAddressMode = address(c.sAddress); d.tAddressMode = address(c.tAddress); d.rAddressMode = address(c.rAddress)
        d.borderColor = border(c.borderColor); d.compareFunction = compare(c.compareFunction)
        d.maxAnisotropy = UInt8(clamping: c.maxAnisotropy ?? 1); d.normalizedCoordinates = c.normalizedCoordinates ?? true
        d.lodMinClamp = Float(c.lodMin ?? 0); d.lodMaxClamp = Float(c.lodMax ?? Double(Float.greatestFiniteMagnitude))
        self.init(d)
    }
}

final class VKFunction: @unchecked Sendable {
    let metallib: [UInt8]
    init(metallib: [UInt8]) { self.metallib = metallib }
}

struct StageStatics {
    var entries: [(Int, UInt64)] = []
    var memory: [VKAllocation] = []
    var usedBuffers: UInt32 = 0
    var name = ""
}

final class VKRenderPipeline: @unchecked Sendable {
    let desc: MetalRenderPipelineDescriptor
    let ready = DispatchGroup()
    var vertex: TranslatedShader?
    var fragment: TranslatedShader?
    var info = yvk_graphics_info()
    var vertexStatics = StageStatics()
    var fragmentStatics = StageStatics()
    var vertexBufferIndices: [Int] = []
    var variants: [UInt32: VkPipeline] = [:]
    var failed: Set<UInt32> = []
    var depthFormat = VK_FORMAT_UNDEFINED
    var stencilFormat = VK_FORMAT_UNDEFINED
    var broken = false
    var released = false

    init(desc: MetalRenderPipelineDescriptor) { self.desc = desc }
    var isBuilt: Bool { vertex != nil && !broken }
}

final class VKComputePipeline: @unchecked Sendable {
    let ready = DispatchGroup()
    var shader: TranslatedShader?
    var statics = StageStatics()
    var variants: [ComputeVariantKey: VkPipeline] = [:]
    var failed: Set<ComputeVariantKey> = []
    var broken = false
    var released = false
    init() {}
}

struct ComputeVariantKey: Hashable {
    var x: Int, y: Int, z: Int
    var threadgroupMemory: [Int]
}

final class VKEvent {
    var semaphore: VkSemaphore?
    var highest: UInt64 = 0
    init(semaphore: VkSemaphore?) { self.semaphore = semaphore }
}

struct IndexAllocator {
    let capacity: UInt32
    private var next: UInt32 = 1
    private var free: [UInt32: [UInt32]] = [:]
    private var freeSet: Set<UInt32> = []
    private(set) var badReleases = 0

    init(capacity: UInt32) { self.capacity = capacity }

    mutating func allocate(_ count: UInt32 = 1) -> UInt32? {
        guard count >= 1 else { return nil }
        if let i = free[count]?.popLast() { freeSet.remove(i); return i }
        guard next + count <= capacity else { return nil }
        defer { next += count }
        return next
    }

    mutating func claim(_ i: UInt32, count: UInt32 = 1) -> Bool {
        guard i != 0, count >= 1, i + count <= capacity else { return false }
        if i >= next {
            for s in next..<i where freeSet.insert(s).inserted { free[1, default: []].append(s) }
            next = i + count
            return true
        }
        guard freeSet.contains(i), let k = free[count]?.firstIndex(of: i) else { return false }
        free[count]!.remove(at: k)
        freeSet.remove(i)
        return true
    }

    mutating func release(_ i: UInt32, count: UInt32 = 1) {
        guard i != 0 else { return }
        guard i + count <= next, freeSet.insert(i).inserted else { badReleases += 1; return }
        free[count, default: []].append(i)
    }
}

final class TransientChunk {
    var buffer: yvk_buffer
    var used = 0
    init(buffer: yvk_buffer) { self.buffer = buffer }
    var capacity: Int { Int(buffer.size) }
}

struct TransientSlice {
    let chunk: TransientChunk
    let offset: Int
    let length: Int
    var vkBuffer: VkBuffer? { chunk.buffer.buffer }
    var address: UInt64 { chunk.buffer.address + UInt64(offset) }
    var pointer: UnsafeMutableRawPointer { chunk.buffer.mapped! + offset }
}

final class Recording {
    let cb: VkCommandBuffer?
    var chunks: [TransientChunk] = []
    var current: TransientChunk?
    var surfaceWrites: [ObjectIdentifier: VKImage] = [:]
    var heapBoundGraphics = false
    var heapBoundCompute = false
    var empty = true
    var waitSemaphore: VkSemaphore?
    var waitValue: UInt64 = 0
    var shaders: [String] = []
    var dispatchNotes: [String] = []

    var writtenSurfaces: [UInt32] = []
    var writtenSurfaceKeys: [SurfaceSyncKey] = []
    var deferred = false

    var draws = 0, largestDraw = 0, indirectDraws = 0

    func noteDraw(_ work: Int) {
        draws += 1
        largestDraw = max(largestDraw, work)
    }

    func noteShaders(_ names: String) {
        if shaders.count < 16 && !shaders.contains(names) { shaders.append(names) }
    }

    var checkpointID: UInt32 = 0
    var dispatchTables: [(pass: Int, command: Int, table: UnsafeMutableRawPointer)] = []
    var lastTable: UnsafeMutableRawPointer?
    var visibilityPool: VkQueryPool?
    var visibilityUsed = 0
    var visibilityPools: [VkQueryPool] = []
    var visibilityReads: [VisibilityRead] = []

    init(cb: VkCommandBuffer?) { self.cb = cb }
}
