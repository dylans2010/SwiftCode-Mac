import Foundation

public protocol DarwinDescriptorObject: AnyObject {
    var fileType: UInt16 { get }
    func lastReferenceClosed()
    var isConfined: Bool { get }
    func descriptorStat() -> DarwinStat
}

extension DarwinDescriptorObject {
    public var isConfined: Bool { false }

    public func descriptorStat() -> DarwinStat {
        DarwinStat(mode: fileType | 0o600, nlink: 1, uid: DarwinFileSystem.guestUID, gid: DarwinFileSystem.guestGID)
    }
}
