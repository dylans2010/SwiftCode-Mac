import YcodeDarwinABI

#if os(Linux) && arch(arm64)
public struct TranslatedGuestMemory: GuestMemoryAccess {
    public let vm: VirtualMachine
    private let translator: TranslatingGuestMemory

    public init(vm: VirtualMachine, pageTables: PageTableBuilder, enforceEL0Permissions: Bool = true) {
        self.vm = vm
        self.translator = TranslatingGuestMemory(
            pageTables: pageTables,
            requireEL0Access: enforceEL0Permissions,
            readPhysical: { pa, count in try vm.read(gpa: pa, count: count) },
            writePhysical: { pa, bytes in try vm.write(gpa: pa, bytes: Array(bytes)) })
    }

    public var pageTables: PageTableBuilder { translator.pageTables }

    public func read(va: UInt64, count: Int) throws -> [UInt8] {
        try validate(va: va, count: count, write: false)
        return try translator.read(va: va, count: count)
    }

    public func write(va: UInt64, bytes: [UInt8]) throws {
        try validate(va: va, count: bytes.count, write: true)
        try translator.write(va: va, bytes: bytes)
    }

    private func validate(va: UInt64, count: Int, write: Bool) throws {
        for piece in try translator.physicalPieces(va: va, count: count, write: write) {
            guard vm.contains(gpa: piece.pa, count: piece.count) else {
                throw KVMError("guest memory access", detail: "VA 0x\(String(va, radix: 16)) reaches PA 0x\(String(piece.pa, radix: 16)), which is not RAM")
            }
        }
    }
}
#endif
