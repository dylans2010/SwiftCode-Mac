import Dispatch
import Foundation

package enum MainActorCheck {
    private static let key = DispatchSpecificKey<UInt8>()
    private static let installed: Bool = {
        DispatchQueue.main.setSpecific(key: key, value: 1)
        return true
    }()

    package static var isCurrent: Bool {
        _ = installed
        return Thread.isMainThread || DispatchQueue.getSpecific(key: key) == 1
    }
}
