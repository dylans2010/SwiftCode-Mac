import Foundation

extension Preferences {
    public var findCustomScopes: [CustomFindScope] {
        get {
            guard let d = defaults.data(forKey: "SwiftCode.findCustomScopes"),
                  let s = try? JSONDecoder().decode([CustomFindScope].self, from: d) else { return [] }
            return s
        }
        set { set("findCustomScopes", try? JSONEncoder().encode(newValue)) }
    }
}
