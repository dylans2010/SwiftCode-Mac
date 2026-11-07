#if DEBUG

import Foundation

public enum DirectServiceAccess {
    public static var gitService: GitService {
        GitService.shared
    }

    public static var xcodeBuildURL: URL {
        URL(fileURLWithPath: "/usr/bin/xcodebuild")
    }
}

#endif
