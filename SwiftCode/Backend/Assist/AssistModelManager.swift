import Foundation

@MainActor
public final class AssistModelManager: ObservableObject {
    public static let shared = AssistModelManager()

    @Published public var customModelID: String {
        didSet {
            UserDefaults.standard.set(customModelID, forKey: "assist.customModelID")
        }
    }

    private init() {
        self.customModelID = UserDefaults.standard.string(forKey: "assist.customModelID") ?? ""
    }

    public var selectedModelID: String {
        let appSetting = AppSettings.shared.selectedAssistModelID
        if !appSetting.isEmpty {
            return AssistModelOption.resolve(id: appSetting)
        }
        if !customModelID.isEmpty {
            return AssistModelOption.resolve(id: customModelID)
        }
        return AssistModelOption.swiftCodeBalanced.id
    }

    public func overrideModelID(for provider: AssistModelProvider) -> String {
        return selectedModelID
    }
}
