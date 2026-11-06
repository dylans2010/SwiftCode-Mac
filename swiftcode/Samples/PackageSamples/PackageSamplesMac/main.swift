import Algorithms
import Codegen
import GreetMacros
import LocalKit
import LocalKitDynamicCore

// The package samples' macOS command-line tool: every kind of package
// product in one target.
print("SWIFTCODE-PKG-SAMPLE mac local: \(LocalKit.greeting); \(LocalKitDynamicCore.describe())")
print("SWIFTCODE-PKG-SAMPLE mac remote: " + [1, 2, 3, 4].chunks(ofCount: 2).map { "\(Array($0))" }.joined(separator: " "))
print("SWIFTCODE-PKG-SAMPLE mac macro: " + #greeting("Mac"))
print("SWIFTCODE-PKG-SAMPLE mac plugin: \(Codegen.message)")
