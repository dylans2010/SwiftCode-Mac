import Codegen
import SwiftUI

@main
struct PluginApp: App {
    static let report = "SWIFTCODE-PKG-SAMPLE plugin: \(Codegen.message); \(AppMessages.title)"
    init() { FileHandle.standardError.write(Data((Self.report + "\n").utf8)) }
    var body: some Scene {
        WindowGroup { Text(Self.report).padding() }
    }
}
