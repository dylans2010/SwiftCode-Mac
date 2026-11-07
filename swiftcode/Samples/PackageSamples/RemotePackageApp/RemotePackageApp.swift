import Algorithms
import SwiftUI

@main
struct RemotePackageApp: App {
    static let report = "SWIFTCODE-PKG-SAMPLE remote: " + [1, 2, 3, 4, 5, 6].chunks(ofCount: 2).map { "\(Array($0))" }.joined(separator: " ")
    init() { FileHandle.standardError.write(Data((Self.report + "\n").utf8)) }
    var body: some Scene {
        WindowGroup { Text(Self.report).padding() }
    }
}
