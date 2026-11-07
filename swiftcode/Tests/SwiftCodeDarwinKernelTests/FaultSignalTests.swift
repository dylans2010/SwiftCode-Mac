import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

struct FaultSignalTests {
    typealias S = DarwinKernel.Signal

    func frame(ec: UInt8, iss: UInt32 = 0) -> TrapFrame {
        TrapFrame(esr: ExceptionSyndrome(ec: ec, iss: iss).raw, kind: TrapFrame.Kind.el0Synchronous.rawValue)
    }

    @Test func mapping() {
        #expect(DarwinKernel.faultSignal(frame(ec: 0x3C, iss: 1)) == S.sigtrap)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x34)) == S.sigtrap)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x00)) == S.sigill)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x18)) == S.sigill)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x19)) == S.sigill)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x1D)) == S.sigill)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x2C)) == S.sigfpe)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x24, iss: 0x07)) == S.sigsegv)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x24, iss: 0x4F)) == S.sigbus)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x24, iss: 0x21)) == S.sigbus)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x20, iss: 0x06)) == S.sigsegv)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x22)) == S.sigbus)
        #expect(DarwinKernel.faultSignal(frame(ec: 0x2F)) == S.sigsegv)
    }
}
