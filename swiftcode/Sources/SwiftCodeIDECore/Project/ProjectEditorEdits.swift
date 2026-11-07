import Foundation
import SwiftCodePlist
import SwiftCodeProject

extension ProjectEditorModel {
    public mutating func setSetting(_ name: String, _ value: String, target: String?, configuration: String) {
        let owner = target.flatMap { self.target(named: $0)?.id } ?? proj.rootObject
        let v = value.trimmingCharacters(in: .whitespaces)
        for c in proj.buildConfigurations(listID: proj[owner]?.string("buildConfigurationList")) where c.string("name") == configuration {
            proj.setBuildSetting(name, v.isEmpty ? nil : .string(v), configuration: c.id)
        }
    }

    @discardableResult
    public mutating func addBuildPhase(isa: String, target name: String) -> String? {
        guard var t = target(named: name) else { return nil }
        let id = proj.makeObjectID()
        var attrs: [(String, PlistValue)] = [("isa", .string(isa)), ("buildActionMask", .string("2147483647")), ("files", .array([]))]
        switch isa {
        case "PBXCopyFilesBuildPhase":
            attrs += [("dstPath", .string("")), ("dstSubfolderSpec", .string("7"))]
        case "PBXShellScriptBuildPhase":
            attrs += [("inputFileListPaths", .array([])), ("inputPaths", .array([])), ("outputFileListPaths", .array([])),
                      ("outputPaths", .array([])), ("shellPath", .string("/bin/sh")), ("shellScript", .string(""))]
        default: break
        }
        attrs.append(("runOnlyForDeploymentPostprocessing", .string("0")))
        proj[id] = PBXObject(id: id, attributes: PlistDictionary(attrs))
        t["buildPhases"] = .array((t.references("buildPhases") + [id]).map(PlistValue.string))
        proj[t.id] = t
        return id
    }

    public mutating func removeBuildPhase(_ id: String) {
        guard let phase = proj[id] else { return }
        for bf in phase.references("files") { proj[bf] = nil }
        for var t in proj.targets where t.references("buildPhases").contains(id) {
            t["buildPhases"] = .array(t.references("buildPhases").filter { $0 != id }.map(PlistValue.string))
            proj[t.id] = t
        }
        proj[id] = nil
    }

    public static let orientations: [(title: String, value: String)] = [
        ("Portrait", "UIInterfaceOrientationPortrait"), ("Upside Down", "UIInterfaceOrientationPortraitUpsideDown"),
        ("Landscape Left", "UIInterfaceOrientationLandscapeLeft"), ("Landscape Right", "UIInterfaceOrientationLandscapeRight"),
    ]

    public static func orientationSetting(device: String) -> String { "INFOPLIST_KEY_UISupportedInterfaceOrientations_\(device)" }

    public func orientations(device: String, target: String, configuration: String) -> Set<String> {
        Set((resolve(target: target, configuration: configuration)?.settings[Self.orientationSetting(device: device)] ?? "")
            .split(separator: " ").map(String.init))
    }

    public mutating func setOrientation(_ value: String, device: String, on: Bool, target: String, configuration: String) {
        var set = orientations(device: device, target: target, configuration: configuration)
        if on { set.insert(value) } else { set.remove(value) }
        let ordered = Self.orientations.map(\.value).filter(set.contains) + set.subtracting(Self.orientations.map(\.value)).sorted()
        setSetting(Self.orientationSetting(device: device), ordered.joined(separator: " "), target: target)
    }
}

extension Capability {
    public var summary: String {
        switch self {
        case .appSandbox: "Restricts the app to its own container and the resources it declares."
        case .hardenedRuntime: "Protects the process from code injection and memory tampering."
        case .outgoingNetwork: "Lets a sandboxed app open outgoing network connections."
        case .incomingNetwork: "Lets a sandboxed app listen for incoming network connections."
        case .userSelectedFilesRead: "Lets a sandboxed app read files the user picks in an open panel."
        case .userSelectedFilesReadWrite: "Lets a sandboxed app read and write files the user picks."
        }
    }

    public var symbolName: String {
        switch self {
        case .appSandbox: "shippingbox"
        case .hardenedRuntime: "lock.shield"
        case .outgoingNetwork: "arrow.up.right.circle"
        case .incomingNetwork: "arrow.down.left.circle"
        case .userSelectedFilesRead: "doc"
        case .userSelectedFilesReadWrite: "doc.badge.ellipsis"
        }
    }
}
