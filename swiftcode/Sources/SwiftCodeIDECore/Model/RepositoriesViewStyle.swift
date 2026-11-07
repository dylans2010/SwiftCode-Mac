import Foundation

public enum RepositoriesViewStyle {
    public static let groupSymbols = ["Branches": "square.stack.3d.up.fill", "Recents": "clock", "Tags": "tag.fill",
                                      "Stashes": "tray", "Remotes": "globe"]
    public static let repositorySymbol = "externaldrive.fill"
    public static let initiallyCollapsed: Set<String> = ["group:Recents", "group:Tags", "group:Stashes", "group:Remotes"]
    public static let modeControlInset = 9.0
    public static let modeControlHeight = 16.0
}
