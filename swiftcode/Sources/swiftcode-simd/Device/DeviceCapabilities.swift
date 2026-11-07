import Foundation

enum DeviceCapabilities {
    static func plist(for type: DeviceType) -> [String: Any] { type.capabilitiesPlist }
}
