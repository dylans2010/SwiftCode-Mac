import LocalKit
import LocalKitDynamicCore
import SwiftUI

@main
struct LocalPackageApp: App {
    static let report = "SWIFTCODE-PKG-SAMPLE local: \(LocalKit.greeting); \(LocalKitDynamicCore.describe())"
    init() { FileHandle.standardError.write(Data((Self.report + "\n").utf8)) }
    var body: some Scene {
        WindowGroup { Text(Self.report).padding() }
    }
}
