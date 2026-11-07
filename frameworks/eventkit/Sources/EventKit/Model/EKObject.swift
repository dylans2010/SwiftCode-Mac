import Foundation

public class EKObject: NSObject {
    public var hasChanges: Bool { false }
    public var isNew: Bool { false }
    public func reset() {}
    public func rollback() {}
    @discardableResult
    public func refresh() -> Bool { true }

    var objectAddress: String {
        "0x" + String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16)
    }
}

public typealias EKEventSearchCallback = (EKEvent, UnsafeMutablePointer<ObjCBool>) -> Void
public typealias EKEventStoreRequestAccessCompletionHandler = (Bool, (any Error)?) -> Void
