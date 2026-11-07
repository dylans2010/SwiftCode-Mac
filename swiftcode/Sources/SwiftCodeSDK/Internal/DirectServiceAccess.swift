#if DEBUG
import Foundation

public enum DirectServiceAccess {
    public static let xcodeBuildURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    public static let gitExecutableURL = URL(fileURLWithPath: "/usr/bin/git")
}
#endif
