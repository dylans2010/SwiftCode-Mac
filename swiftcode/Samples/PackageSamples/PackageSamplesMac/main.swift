import Algorithms
import Codegen
import GreetMacros
import LocalKit
import LocalKitDynamicCore

print("SWIFTCODE-PKG-SAMPLE mac local: \(LocalKit.greeting); \(LocalKitDynamicCore.describe())")
print("SWIFTCODE-PKG-SAMPLE mac remote: " + [1, 2, 3, 4].chunks(ofCount: 2).map { "\(Array($0))" }.joined(separator: " "))
print("SWIFTCODE-PKG-SAMPLE mac macro: " + #greeting("Mac"))
print("SWIFTCODE-PKG-SAMPLE mac plugin: \(Codegen.message)")
