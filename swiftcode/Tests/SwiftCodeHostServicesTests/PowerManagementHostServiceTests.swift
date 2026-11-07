import Foundation
import Testing
@testable import SwiftCodeDarwinKernel
@testable import SwiftCodeHostServices

@Suite struct PowerManagementHostServiceTests {
    func request(_ id: Int32, _ scalars: [Int32] = [], ool: Bool = false) -> MachHostReceivedMessage {
        var body = PowerManagementHostService.ndr
        for v in scalars { body += PowerManagementHostService.le(v) }
        return MachHostReceivedMessage(bits: ool ? MachMsgBits.complex : 0, replyPort: 0, replyType: 0, localPort: 0, voucher: 0,
                                       id: id, descriptors: ool ? [.ool(data: [0x62, 0x70], copy: 1, volatile: false)] : [],
                                       body: body, size: 0, seqno: 0, context: 0, sender: nil)
    }

    func words(_ b: [UInt8]) -> [Int32] {
        stride(from: 8, to: b.count, by: 4).map { i in
            Int32(bitPattern: UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24)
        }
    }

    @Test func assertionsAreGranted() throws {
        let s = try PowerManagementHostService(host: DarwinSystem().hostTask, log: { _ in })
        let a = try #require(s.answer(request(73007, [2], ool: true)))
        let b = try #require(s.answer(request(73007, [2], ool: true)))
        #expect(a.descriptors.isEmpty && Array(a.body.prefix(8)) == PowerManagementHostService.ndr)
        #expect(words(a.body).count == 5 && words(a.body)[0] == 0 && words(a.body)[4] == 0)
        #expect(words(a.body)[1] != 0 && words(b.body)[1] == words(a.body)[1] + 1)
        #expect(words(try #require(s.answer(request(73009, [words(a.body)[1], 0]))).body) == [0, 0, 0, 0, 0])
        #expect(words(try #require(s.answer(request(73030))).body) == [0, 0xF, 0])
        let u = words(try #require(s.answer(request(73012, [0, 2, 0], ool: true))).body)
        #expect(u.count == 4 && u[0] == 0 && u[1] != 0 && u[3] == 0)
        #expect(words(try #require(s.answer(request(73099))).body) == [-303])
    }
}
