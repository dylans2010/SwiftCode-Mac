import Foundation
import YcodeDarwinKernel

enum SCDynamicStoreNetworkState {
    static let serviceID = "59C1CF50-4D8F-4C53-9C7E-79434F444531"

    static func current() -> [String: Any] {
        guard GuestNetwork.enabled else { return [:] }
        let interfaces = GuestNetwork.interfaces
        var store: [String: Any] = [:]
        store["State:/Network/Interface"] = ["Interfaces": interfaces.map(\.name)]
        for i in interfaces {
            let base = "State:/Network/Interface/\(i.name)"
            if !i.ipv4.isEmpty {
                var v4: [String: Any] = ["Addresses": i.ipv4.map(\.address), "SubnetMasks": i.ipv4.map(\.netmask)]
                let broadcasts = i.ipv4.compactMap(\.broadcast)
                if broadcasts.count == i.ipv4.count, !broadcasts.isEmpty { v4["BroadcastAddresses"] = broadcasts }
                store[base + "/IPv4"] = v4
            }
            if !i.ipv6.isEmpty {
                store[base + "/IPv6"] = ["Addresses": i.ipv6.map(\.address), "PrefixLength": i.ipv6.map(\.prefixLength),
                                         "Flags": i.ipv6.map { _ in 0 }]
            }
            if !i.isLoopback { store[base + "/Link"] = ["Active": true] }
        }
        let dnsServers = GuestNetwork.nameServers
        if let primary = interfaces.first(where: { !$0.isLoopback && !$0.ipv4.isEmpty }) {
            var global: [String: Any] = ["PrimaryInterface": primary.name, "PrimaryService": serviceID]
            var service: [String: Any] = ["Addresses": primary.ipv4.map(\.address), "SubnetMasks": primary.ipv4.map(\.netmask),
                                          "InterfaceName": primary.name]
            if let r = primary.router4 {
                global["Router"] = r
                service["Router"] = r
            }
            store["State:/Network/Global/IPv4"] = global
            store["State:/Network/Service/\(serviceID)/IPv4"] = service
            let global6 = primary.ipv6.filter { !$0.address.lowercased().hasPrefix("fe80") }
            if !global6.isEmpty {
                var g6: [String: Any] = ["PrimaryInterface": primary.name, "PrimaryService": serviceID]
                var s6: [String: Any] = ["Addresses": global6.map(\.address), "PrefixLength": global6.map(\.prefixLength),
                                         "InterfaceName": primary.name]
                if let r = primary.router6 {
                    g6["Router"] = r
                    s6["Router"] = r
                }
                store["State:/Network/Global/IPv6"] = g6
                store["State:/Network/Service/\(serviceID)/IPv6"] = s6
            }
            if !dnsServers.isEmpty {
                store["State:/Network/Service/\(serviceID)/DNS"] = ["ServerAddresses": dnsServers]
            }
        }
        if !dnsServers.isEmpty { store["State:/Network/Global/DNS"] = ["ServerAddresses": dnsServers] }
        if let primary = interfaces.first(where: { !$0.isLoopback && !$0.ipv4.isEmpty }) {
            store["Setup:/Network/Global/IPv4"] = ["ServiceOrder": [serviceID]]
            store["Setup:/Network/Service/\(serviceID)"] = ["UserDefinedName": "Ethernet"]
            store["Setup:/Network/Service/\(serviceID)/Interface"] = ["DeviceName": primary.name, "Hardware": "Ethernet",
                                                                      "Type": "Ethernet", "UserDefinedName": "Ethernet"]
            store["Setup:/Network/Service/\(serviceID)/IPv4"] = ["ConfigMethod": "DHCP"]
            store["Setup:/Network/Service/\(serviceID)/IPv6"] = ["ConfigMethod": "Automatic"]
            store["Setup:/Network/Service/\(serviceID)/Proxies"] = ["ExceptionsList": ["*.local", "169.254/16"], "FTPPassive": 1]
            store["State:/Network/Service/\(serviceID)"] = [String: Any]()
        }
        store["State:/Network/MulticastDNS"] = ["local", "254.169.in-addr.arpa", "8.e.f.ip6.arpa", "9.e.f.ip6.arpa",
                                                "a.e.f.ip6.arpa", "b.e.f.ip6.arpa"]
        store["State:/Network/PrivateDNS"] = [String]()
        store["State:/Network/Global/Proxies"] = ["ExceptionsList": ["*.local", "169.254/16"], "FTPPassive": 1,
                                                  "HTTPEnable": 0, "HTTPSEnable": 0]
        return store
    }

    static func select(_ store: [String: Any], keys: [String], patterns: [String]) -> [String] {
        var out = Set(keys.filter { store[$0] != nil })
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: "^(?:" + p + ")$") else { continue }
            for k in store.keys where re.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)) != nil { out.insert(k) }
        }
        return out.sorted()
    }

    static func serialize(_ v: Any) -> [UInt8]? {
        guard let d = try? PropertyListSerialization.data(fromPropertyList: v, format: .binary, options: 0) else { return nil }
        return [UInt8](d)
    }

    static func unserialize(_ b: [UInt8]) -> Any? {
        guard !b.isEmpty else { return nil }
        return try? PropertyListSerialization.propertyList(from: Data(b), options: [], format: nil)
    }
}
