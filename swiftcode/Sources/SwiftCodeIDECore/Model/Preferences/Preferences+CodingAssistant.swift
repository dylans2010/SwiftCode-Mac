import Foundation
import SwiftCodeAssistant

extension Preferences {
    public var codingAssistant: AssistantSettings {
        get {
            guard let d = defaults.data(forKey: "SwiftCode.codingAssistant"),
                  let s = try? JSONDecoder().decode(AssistantSettings.self, from: d) else { return AssistantSettings() }
            return s
        }
        set { set("codingAssistant", try? JSONEncoder().encode(newValue)) }
    }
}
