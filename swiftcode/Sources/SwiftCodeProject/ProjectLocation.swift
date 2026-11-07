import Foundation

extension PBXProj {
    public static func locate(_ path: String) -> (file: URL, projectName: String) {
        var url = URL(fileURLWithPath: path)
        if url.pathExtension == "xcodeproj" { url.appendPathComponent("project.pbxproj") }
        let bundle = url.deletingLastPathComponent()
        let name = bundle.pathExtension == "xcodeproj" ? bundle.deletingPathExtension().lastPathComponent : bundle.lastPathComponent
        return (url, name)
    }
}
