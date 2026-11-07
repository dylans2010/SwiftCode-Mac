import Foundation
import YcodePlist

extension PBXProj {
    public mutating func setBuildSetting(_ key: String, _ value: PlistValue?, configuration id: String) {
        guard var config = self[id], config.isa == "XCBuildConfiguration" else { return }
        var settings = config["buildSettings"]?.dictionary ?? PlistDictionary()
        guard settings[key] != value else { return }
        settings[key] = value
        config["buildSettings"] = .dictionary(settings)
        self[id] = config
    }

    public mutating func setBuildSetting(_ key: String, _ value: PlistValue?, inListOf owner: String) {
        for c in buildConfigurations(listID: self[owner]?.string("buildConfigurationList")) {
            setBuildSetting(key, value, configuration: c.id)
        }
    }

    public static func fileType(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": "sourcecode.swift"
        case "m": "sourcecode.c.objc"
        case "mm": "sourcecode.cpp.objcpp"
        case "c": "sourcecode.c.c"
        case "cpp", "cc", "cxx": "sourcecode.cpp.cpp"
        case "h": "sourcecode.c.h"
        case "hpp": "sourcecode.cpp.h"
        case "metal": "sourcecode.metal"
        case "plist": "text.plist.xml"
        case "strings": "text.plist.strings"
        case "xcstrings": "text.json.xcstrings"
        case "xcconfig": "text.xcconfig"
        case "json": "text.json"
        case "md": "net.daringfireball.markdown"
        case "xcassets": "folder.assetcatalog"
        case "storyboard": "file.storyboard"
        case "xib": "file.xib"
        case "entitlements": "text.plist.entitlements"
        case "framework": "wrapper.framework"
        case "a": "archive.ar"
        case "dylib": "compiled.mach-o.dylib"
        case "png": "image.png"
        case "jpg", "jpeg": "image.jpeg"
        case "gif": "image.gif"
        case "pdf": "image.pdf"
        case "s": "sourcecode.asm"
        case "stringsdict": "text.plist.stringsdict"
        case "sh": "text.script.sh"
        case "py": "text.script.python"
        case "html": "text.html"
        case "xml": "text.xml"
        case "rtf": "text.rtf"
        case "xcdatamodel": "wrapper.xcdatamodel"
        case "xcdatamodeld": "wrapper.xcdatamodeld"
        case "xcframework": "wrapper.xcframework"
        case "bundle": "wrapper.plug-in"
        case "app": "wrapper.application"
        case "tbd": "sourcecode.text-based-dylib-definition"
        default: "text"
        }
    }

    @discardableResult
    public mutating func addFileReference(path: String, to group: String) -> String {
        let id = makeObjectID()
        self[id] = PBXObject(id: id, attributes: PlistDictionary([
            ("isa", .string("PBXFileReference")),
            ("lastKnownFileType", .string(Self.fileType(forPath: path))),
            ("path", .string(path)),
            ("sourceTree", .string("<group>")),
        ]))
        if var g = self[group] {
            g["children"] = .array((g["children"]?.array ?? []) + [.string(id)])
            self[group] = g
        }
        return id
    }

    @discardableResult
    public mutating func addBuildFile(fileReference: String, to phase: String) -> String {
        let id = makeObjectID()
        self[id] = PBXObject(id: id, attributes: PlistDictionary([("isa", .string("PBXBuildFile")), ("fileRef", .string(fileReference))]))
        if var p = self[phase] {
            p["files"] = .array((p["files"]?.array ?? []) + [.string(id)])
            self[phase] = p
        }
        return id
    }

    public mutating func removeBuildFile(_ id: String) {
        for (pid, var phase) in objects where phase.references("files").contains(id) {
            phase["files"] = .array(phase.references("files").filter { $0 != id }.map(PlistValue.string))
            self[pid] = phase
        }
        self[id] = nil
    }

    public mutating func removeFileReference(_ id: String) {
        for bf in objects.values where bf.isa == "PBXBuildFile" && bf.string("fileRef") == id { removeBuildFile(bf.id) }
        for (gid, var g) in objects where g.references("children").contains(id) {
            g["children"] = .array(g.references("children").filter { $0 != id }.map(PlistValue.string))
            self[gid] = g
        }
        self[id] = nil
    }

    public func buildPhases(ofTarget id: String) -> [PBXObject] {
        (self[id]?.references("buildPhases") ?? []).compactMap { self[$0] }
    }

    public func fileReference(ofBuildFile id: String) -> PBXObject? {
        self[id]?.string("fileRef").flatMap { self[$0] }
    }
}
