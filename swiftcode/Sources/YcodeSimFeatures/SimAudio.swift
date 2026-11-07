import Foundation

public enum AudioDeviceChoice: Equatable, Sendable {
    case none
    case system
    case device(String)

    public init(argument: String) {
        switch argument.lowercased() {
        case "none", "off": self = .none
        case "system", "default", "use-system-settings": self = .system
        default: self = .device(argument)
        }
    }

    public var argument: String {
        switch self {
        case .none: "none"
        case .system: "system"
        case .device(let uid): uid
        }
    }

    public var title: String {
        switch self {
        case .none: "None"
        case .system: "System"
        case .device(let uid): uid
        }
    }
}

public struct SimAudioSettings: Equatable, Sendable {
    public var volume: Int = SimAudio.defaultVolume
    public var output: AudioDeviceChoice = .system
    public var input: AudioDeviceChoice = .system

    public init(volume: Int = SimAudio.defaultVolume, output: AudioDeviceChoice = .system, input: AudioDeviceChoice = .system) {
        self.volume = volume
        self.output = output
        self.input = input
    }
}

public enum SimAudio {
    public static let defaultVolume = 60
    public static let ringerState = 1
    public static let swiftcodeOutputUID = "dev.swiftcode.simulator.audio.output"

    public static let outputDevices: [(uid: String, name: String)] = [(swiftcodeOutputUID, "SwiftCode Simulator Output")]
    public static let inputDevices: [(uid: String, name: String)] = []

    public static func resolvedUID(_ choice: AudioDeviceChoice, output: Bool) -> String {
        switch choice {
        case .none: ""
        case .system: output ? swiftcodeOutputUID : ""
        case .device(let uid): uid
        }
    }

    public static func hostFile(_ s: SimAudioSettings) -> [String: Any] {
        ["sim_output_device_uid": resolvedUID(s.output, output: true),
         "sim_input_device_uid": resolvedUID(s.input, output: false),
         "useHostDefaultOutputDevice": s.output == .system,
         "useHostDefaultInputDevice": s.input == .system]
    }

    public static func settingsFile(_ s: SimAudioSettings) -> [String: Any] {
        ["sim_input_device_uid": resolvedUID(s.input, output: false),
         "sim_output_device_uid": resolvedUID(s.output, output: true),
         "sim_ringer_state": ringerState,
         "sim_volume": min(100, max(0, s.volume))]
    }

    public static func settings(hostFile: [String: Any]?, settingsFile: [String: Any]?) -> SimAudioSettings {
        var s = SimAudioSettings()
        if let v = (settingsFile?["sim_volume"] as? NSNumber)?.intValue { s.volume = min(100, max(0, v)) }
        func choice(_ uidKey: String, _ flagKey: String) -> AudioDeviceChoice {
            guard let h = hostFile else { return .system }
            if (h[flagKey] as? NSNumber)?.boolValue ?? (h[flagKey] as? Bool) ?? false { return .system }
            let uid = h[uidKey] as? String ?? ""
            return uid.isEmpty ? .none : .device(uid)
        }
        s.output = choice("sim_output_device_uid", "useHostDefaultOutputDevice")
        s.input = choice("sim_input_device_uid", "useHostDefaultInputDevice")
        return s
    }

    public static let volumeStep = 10
}
