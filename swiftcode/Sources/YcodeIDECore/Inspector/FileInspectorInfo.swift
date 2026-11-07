import Foundation

public struct FileInspectorInfo: Equatable {
    public var workingCopy: String?
    public var relativePath: String?
    public var memberships: [TargetMembership]
    public var inSynchronizedFolder: Bool
    public var isPackageFile: Bool
    public init(workingCopy: String? = nil, relativePath: String? = nil, memberships: [TargetMembership] = [],
                inSynchronizedFolder: Bool = false, isPackageFile: Bool = false) {
        self.workingCopy = workingCopy
        self.relativePath = relativePath
        self.memberships = memberships
        self.inSynchronizedFolder = inSynchronizedFolder
        self.isPackageFile = isPackageFile
    }
}
