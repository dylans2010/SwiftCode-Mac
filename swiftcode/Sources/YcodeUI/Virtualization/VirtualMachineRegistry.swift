import Foundation
import YcodeHypervisor

public struct VMRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var osType: String
    public var version: String
    public var status: String
    public var cpuCores: Int
    public var memoryMB: Int
    public var storageGB: Int
    public var imagePath: String
    public var createdDate: Date
    public var bootCount: Int

    public init(id: UUID = UUID(), name: String, osType: String, version: String = "",
                status: String = "Stopped", cpuCores: Int = 2, memoryMB: Int = 2048,
                storageGB: Int = 20, imagePath: String = "", createdDate: Date = Date(),
                bootCount: Int = 0) {
        self.id = id
        self.name = name
        self.osType = osType
        self.version = version
        self.status = status
        self.cpuCores = cpuCores
        self.memoryMB = memoryMB
        self.storageGB = storageGB
        self.imagePath = imagePath
        self.createdDate = createdDate
        self.bootCount = bootCount
    }

    public static let knownOSTypes = ["Ubuntu", "Debian", "Fedora", "Alpine"]
}

public final class VirtualMachineRegistry: @unchecked Sendable {
    public static let shared = VirtualMachineRegistry()

    public var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent("VirtualMachines", isDirectory: true)
    }

    public var registryURL: URL { directory.appendingPathComponent("registry.json") }

    private var records: [VMRecord] = []
    private let lock = NSLock()

    public init() {
        load()
    }

    public func all() -> [VMRecord] { lock.withLock { records } }

    public func record(id: UUID) -> VMRecord? { lock.withLock { records.first { $0.id == id } } }

    @discardableResult
    public func create(name: String, osType: String, version: String = "", cpuCores: Int = 2,
                       memoryMB: Int = 2048, storageGB: Int = 20, imagePath: String = "") throws -> VMRecord {
        if !imagePath.isEmpty, !FileManager.default.fileExists(atPath: imagePath) {
            throw VirtualMachineRegistryError.imageNotFound(imagePath)
        }
        let record = VMRecord(name: name, osType: osType, version: version,
                              cpuCores: max(1, cpuCores), memoryMB: max(256, memoryMB),
                              storageGB: max(1, storageGB), imagePath: imagePath)
        lock.withLock { records.append(record) }
        try save()
        return record
    }

    public func duplicate(id: UUID) throws -> VMRecord {
        guard let original = record(id: id) else { throw VirtualMachineRegistryError.notFound }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) copy"
        copy.status = "Stopped"
        copy.createdDate = Date()
        lock.withLock { records.append(copy) }
        try save()
        return copy
    }

    public func delete(id: UUID) throws {
        lock.withLock { records.removeAll { $0.id == id } }
        try save()
    }

    public func rename(id: UUID, to name: String) throws {
        lock.withLock {
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].name = name }
        }
        try save()
    }

    public func updateStatus(id: UUID, status: String) throws {
        lock.withLock {
            if let index = records.firstIndex(where: { $0.id == id }) { records[index].status = status }
        }
        try save()
    }

    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(lock.withLock { records })
        try data.write(to: registryURL, options: .atomic)
    }

    public func scanVirtualDiskFiles() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let allowedExtensions: Set<String> = ["img", "iso", "qcow2", "raw", "vmdk", "vhdx"]
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return }

        lock.withLock {
            var updated = records
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }
                let path = fileURL.path
                if updated.contains(where: { $0.imagePath == path }) { continue }

                let attrs = (try? fm.attributesOfItem(atPath: path)) ?? [:]
                let fileSize = (attrs[.size] as? Int64) ?? 0
                let createdDate = (attrs[.creationDate] as? Date) ?? Date()
                let storageGB = max(1, Int(fileSize / (1024 * 1024 * 1024)))

                let filename = fileURL.deletingPathExtension().lastPathComponent
                let lowerName = filename.lowercased()
                let osType: String
                if lowerName.contains("ubuntu") { osType = "Ubuntu" }
                else if lowerName.contains("debian") { osType = "Debian" }
                else if lowerName.contains("fedora") { osType = "Fedora" }
                else if lowerName.contains("alpine") { osType = "Alpine" }
                else { osType = "Linux" }

                let newRecord = VMRecord(
                    name: filename.replacingOccurrences(of: "-", with: " ").capitalized,
                    osType: osType,
                    version: "",
                    status: "Stopped",
                    cpuCores: 2,
                    memoryMB: 2048,
                    storageGB: storageGB,
                    imagePath: path,
                    createdDate: createdDate,
                    bootCount: 0
                )
                updated.append(newRecord)
            }
            records = updated
        }
        try? save()
    }

    public func verifyDiskImages() {
        lock.withLock {
            for i in records.indices {
                if !records[i].imagePath.isEmpty {
                    if !FileManager.default.fileExists(atPath: records[i].imagePath) {
                        records[i].status = "Image Missing"
                    }
                }
            }
        }
    }

    public func load() {
        let fm = FileManager.default
        if fm.fileExists(atPath: registryURL.path),
           let data = try? Data(contentsOf: registryURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([VMRecord].self, from: data) {
                lock.withLock { records = decoded }
            }
        }
        scanVirtualDiskFiles()
        verifyDiskImages()
    }
}

public enum VirtualMachineRegistryError: Error, LocalizedError, Equatable {
    case notFound
    case imageNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "That virtual machine no longer exists in the registry."
        case .imageNotFound(let path): return "No disk image exists at \(path)."
        }
    }
}

public struct VirtualMachineHostProbe: Sendable, Equatable {
    public var hypervisorAvailable: Bool
    public var vcpusAllocated: Int
    public var ramBytesAllocated: Int
    public var error: String?

    public init(hypervisorAvailable: Bool, vcpusAllocated: Int = 0, ramBytesAllocated: Int = 0, error: String? = nil) {
        self.hypervisorAvailable = hypervisorAvailable
        self.vcpusAllocated = vcpusAllocated
        self.ramBytesAllocated = ramBytesAllocated
        self.error = error
    }
}

public enum VirtualMachineHostProbeRunner {
    public static func probe() -> VirtualMachineHostProbe {
        guard Hypervisor.isAvailable else {
            return VirtualMachineHostProbe(hypervisorAvailable: false,
                                           error: "KVM is not available on this host (macOS has no KVM). Virtual machines cannot be allocated here.")
        }
        #if os(Linux) && arch(arm64)
        do {
            let vm = try VirtualMachine(ramSize: 256 << 20)
            let vcpu = try vm.makeVCPU()
            _ = vcpu
            vm.close()
            return VirtualMachineHostProbe(hypervisorAvailable: true, vcpusAllocated: 1, ramBytesAllocated: 256 << 20)
        } catch {
            return VirtualMachineHostProbe(hypervisorAvailable: true, error: "KVM is present but a VM could not be allocated: \(error)")
        }
        #else
        return VirtualMachineHostProbe(hypervisorAvailable: false,
                                       error: "KVM is not available on this host (macOS has no KVM). Virtual machines cannot be allocated here.")
        #endif
    }
}

public enum VirtualMachineAllocationError: Error, LocalizedError {
    case unavailable
    public var errorDescription: String? {
        "Virtual machine allocation needs an arm64 Linux host with KVM; this host has none."
    }
}

public final class AllocatedVirtualMachine: @unchecked Sendable {
    public let record: VMRecord
    #if os(Linux) && arch(arm64)
    private var vm: VirtualMachine?
    private var vcpus: [VCPU] = []
    #endif
    public private(set) var isAllocated = false

    public init(record: VMRecord) {
        self.record = record
    }

    public func allocate() throws {
        guard !isAllocated else { return }
        #if os(Linux) && arch(arm64)
        let vm = try VirtualMachine(ramSize: max(256, record.memoryMB) << 20)
        var created: [VCPU] = []
        for _ in 0..<max(1, record.cpuCores) {
            created.append(try vm.makeVCPU())
        }
        self.vm = vm
        self.vcpus = created
        self.isAllocated = true
        #else
        throw VirtualMachineAllocationError.unavailable
        #endif
    }

    public func release() {
        #if os(Linux) && arch(arm64)
        vm?.close()
        vm = nil
        vcpus = []
        #endif
        isAllocated = false
    }

    deinit {
        #if os(Linux) && arch(arm64)
        vm?.close()
        #endif
    }
}
