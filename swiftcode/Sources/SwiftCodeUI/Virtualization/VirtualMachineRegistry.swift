import Foundation
import SwiftCodeHypervisor

/// The virtualization console's model (gap closure, specs/ide/
/// gap-closure-windows-artboards.md §7).
///
/// Legacy's `VirtualizationWindowManager` showed a "Virtualization
/// Console" (1100×750) over `SCVirtualizationEngine`, which
/// instantiates real `VZVirtualMachine`s — Apple
/// Virtualization.framework, macOS-only. SwiftCode's engine is the
/// Linux-KVM `SwiftCodeHypervisor`: `Hypervisor.isAvailable`,
/// `VirtualMachine(ramGPA:ramSize:)` (a bare KVM VM — RAM only),
/// `makeVCPU`, memory slots, `close()`. It has no named-VM model,
/// no guest-kernel loading, no disk, no display, and no VZ
/// wrapper; on macOS KVM does not exist.
///
/// So this console is honest about what it is: a **registry of
/// VM definitions** (a ported subset of Legacy's `VirtualMachine`
/// model) + a **host probe** that really allocates a KVM VM +
/// **Allocate / Release**, not Start / Stop. Allocate reserves a
/// real KVM VM (RAM + vCPUs) and holds it; Release closes it. No
/// guest kernel is loaded and there is no display — the window
/// says so plainly. Booting a guest, snapshots, and networking
/// need a VZ wrapper on macOS or a kernel-boot path on KVM, and
/// are not claimed here.
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

    /// The guest OS types Legacy's wizard offered.
    public static let knownOSTypes = ["Ubuntu", "Debian", "Fedora", "Alpine"]
}

/// The persisted registry of VM definitions, at Application
/// Support `SwiftCode/VirtualMachines/registry.json` (the same idea as
/// the artboard store: user data, never inside a workspace).
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

    /// Creates a definition (validating the disk image path when
    /// one is given) and persists it. Returns the stored record.
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

    public func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: registryURL.path),
              let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([VMRecord].self, from: data) {
            lock.withLock { records = decoded }
        }
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

/// The result of probing the host hypervisor (a real KVM
/// allocation attempt, not a capability guess).
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
    /// Probes the host by really doing it: checks
    /// `Hypervisor.isAvailable`, then creates a bare KVM VM with
    /// 256 MB of RAM and one vCPU, then closes it. On a Linux host
    /// with /dev/kvm this succeeds; on macOS `isAvailable` is
    /// false and the probe reports that honestly instead of
    /// claiming a VM can run.
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

/// Allocation is only possible on an arm64 Linux host with KVM; elsewhere
/// the console reports it honestly.
public enum VirtualMachineAllocationError: Error, LocalizedError {
    case unavailable
    public var errorDescription: String? {
        "Virtual machine allocation needs an arm64 Linux host with KVM; this host has none."
    }
}

/// A real, held KVM allocation for a registry record: the VM the
/// console's Allocate button reserves, released by `release()`.
/// No guest kernel is loaded and there is no display — this is
/// allocation, not a boot.
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

    /// Allocates the KVM VM (RAM + vCPUs) and holds it. Throws the
    /// real `KVMError` when allocation fails.
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
