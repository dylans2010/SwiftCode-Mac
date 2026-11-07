public enum MetalSystemUI {
    public static let labels: Set<String> = ["com.apple.backboardd", "com.apple.SpringBoard"]
    public static let executableSuffixes = ["/usr/libexec/backboardd", "/System/Library/CoreServices/SpringBoard.app/SpringBoard"]

    public static func isSystemUI(label: String?, executablePath: String?) -> Bool {
        if let label, labels.contains(label) { return true }
        guard let path = executablePath else { return false }
        return executableSuffixes.contains { path.hasSuffix($0) }
    }
}
