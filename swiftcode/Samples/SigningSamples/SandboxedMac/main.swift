import Foundation

let home = NSHomeDirectory()
let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil || home.contains("/Library/Containers/")
let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Bundle.main.bundleIdentifier.map { $0 + ".shared" } ?? "")
print("SWIFTCODE-SIGNING-SAMPLE sandboxed=\(sandboxed) appGroupContainer=\(group == nil ? "none" : "yes")")
