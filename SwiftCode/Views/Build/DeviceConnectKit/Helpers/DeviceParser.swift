import Foundation

public struct DeviceParser {
    public static func parseXCDeviceList(_ jsonString: String) -> [ConnectedDevice] {
        guard let data = jsonString.data(using: .utf8) else { return [] }

        struct XCDeviceItem: Decodable {
            let name: String?
            let model: String?
            let platform: String?
            let operatingSystemVersion: String?
            let identifier: String?
            let modelUTI: String?
            let isWirelesslyConnected: Bool?
            let isConnected: Bool?
            let isAvailable: Bool?
        }

        guard let items = try? JSONDecoder().decode([XCDeviceItem].self, from: data) else {
            return []
        }

        return items.compactMap { item in
            guard let id = item.identifier else { return nil }
            return ConnectedDevice(
                name: item.name ?? "Apple Device",
                model: item.model ?? "Generic",
                productType: item.modelUTI ?? "com.apple.device",
                platform: item.platform ?? "iOS",
                osVersion: item.operatingSystemVersion ?? "1.0",
                buildVersion: "Release",
                architecture: "arm64",
                udid: id,
                isConnected: item.isConnected ?? true,
                isAvailable: item.isAvailable ?? true,
                isWireless: item.isWirelesslyConnected ?? false
            )
        }
    }
}
