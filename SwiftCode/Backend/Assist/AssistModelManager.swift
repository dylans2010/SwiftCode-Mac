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
        if !customModelID.isEmpty {
            return customModelID
        }
        return AppSettings.shared.selectedAssistModelID
    }

    public func overrideModelID(for provider: AssistModelProvider) -> String {
        if !customModelID.isEmpty {
            return customModelID
        }
        // Fallback to provider defaults if needed
        return AppSettings.shared.selectedAssistModelID
    }
}
