import Foundation

public enum ReverseSettings {
    public static var reverseEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "assist.reverseEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assist.reverseEnabled") }
    }
}
