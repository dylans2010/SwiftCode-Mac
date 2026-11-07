import GreetMacros
import SwiftUI

@main
struct MacroApp: App {
    static let report = "SWIFTCODE-PKG-SAMPLE macro: " + #greeting("SwiftCode")
    init() { FileHandle.standardError.write(Data((Self.report + "\n").utf8)) }
    var body: some Scene {
        WindowGroup { Text(Self.report).padding() }
    }
}
