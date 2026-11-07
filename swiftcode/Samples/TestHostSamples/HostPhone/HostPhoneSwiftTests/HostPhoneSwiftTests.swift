import Testing
@testable import HostPhone

struct HostPhoneSwiftTests {
    @Test func title() {
        #expect(PhoneModel.title == "HostPhone")
    }

    @Test func failsOnPurpose() {
        #expect(PhoneModel.title.count == 3)
    }
}
