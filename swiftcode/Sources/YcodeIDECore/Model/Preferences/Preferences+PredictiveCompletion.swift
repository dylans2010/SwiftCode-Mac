import Foundation
import YcodeCompletion

extension Preferences {
    public var predictiveCompletion: PredictiveCompletionSettings {
        get { PredictiveCompletionSettings.load(from: defaults) }
        set {
            newValue.save(to: defaults)
            changed()
        }
    }

    public var sharedOllamaURL: String { codingAssistant.ollamaURL }
}
