import Foundation
import SwiftCodeSDK

let args = Array(CommandLine.arguments.dropFirst())
let path = args.first ?? FileManager.default.currentDirectoryPath

let inspector = ProjectInspector()
do {
    let metadata = try inspector.inspect(at: path)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)
    print(String(decoding: data, as: UTF8.self))
    exit(0)
} catch {
    print("Error inspecting project: \(error.localizedDescription)")
    exit(1)
}
