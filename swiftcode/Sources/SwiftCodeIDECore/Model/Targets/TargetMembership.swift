import Foundation
import SwiftCodePlist
import SwiftCodeProject

public struct TargetMembership: Equatable, Sendable {
    public var targetID: String
    public var name: String
    public var isMember: Bool
    public var isEditable: Bool
    public var kind: String { "Default" }
    package init(targetID: String, name: String, isMember: Bool, isEditable: Bool) {
        self.targetID = targetID
        self.name = name
        self.isMember = isMember
        self.isEditable = isEditable
    }
}

extension PBXProj {
    package enum FilePlace { case reference(String), synchronized(group: String, relative: String) }

    package func place(ofFile path: String, projectDirectory: URL) -> FilePlace? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        let parents = parentMap()
        for ref in objects.values where ref.isa == "PBXFileReference" {
            if let p = resolvedPath(of: ref.id, projectDirectory: projectDirectory, parents: parents),
               URL(fileURLWithPath: p).standardizedFileURL.path == target { return .reference(ref.id) }
        }
        for g in objects.values where g.isa == "PBXFileSystemSynchronizedRootGroup" {
            guard let p = resolvedPath(of: g.id, projectDirectory: projectDirectory, parents: parents) else { continue }
            let root = URL(fileURLWithPath: p).standardizedFileURL.path + "/"
            if target.hasPrefix(root) { return .synchronized(group: g.id, relative: String(target.dropFirst(root.count))) }
        }
        return nil
    }

    func exceptionSet(group: String, target: String) -> PBXObject? {
        self[group]?.references("exceptions").compactMap { self[$0] }
            .first { $0.isa == "PBXFileSystemSynchronizedBuildFileExceptionSet" && $0.string("target") == target }
    }

    public func targetMemberships(ofFile path: String, projectDirectory: URL) -> [TargetMembership] {
        let place = place(ofFile: path, projectDirectory: projectDirectory)
        return targets.map { t in
            let name = t.string("name") ?? t.id
            switch place {
            case .reference(let ref)?:
                let member = buildPhases(ofTarget: t.id).contains { phase in
                    phase.references("files").contains { fileReference(ofBuildFile: $0)?.id == ref }
                }
                return TargetMembership(targetID: t.id, name: name, isMember: member, isEditable: true)
            case .synchronized(let group, let rel)?:
                let key = SynchronizedFolder.membershipKey(forRelativePath: rel)
                return TargetMembership(targetID: t.id, name: name,
                                        isMember: isSynchronizedMember(key: key, folder: group, target: t.id), isEditable: true)
            case nil:
                return TargetMembership(targetID: t.id, name: name, isMember: false, isEditable: false)
            }
        }
    }

    @discardableResult
    public mutating func setMembership(ofFile path: String, target: String, member: Bool, projectDirectory: URL) -> Bool {
        guard self[target] != nil, let place = place(ofFile: path, projectDirectory: projectDirectory) else { return false }
        switch place {
        case .reference(let ref):
            let phases = buildPhases(ofTarget: target)
            if member {
                guard !phases.contains(where: { $0.references("files").contains { fileReference(ofBuildFile: $0)?.id == ref } }) else { return false }
                let isa = Self.isSource(path) ? "PBXSourcesBuildPhase" : "PBXResourcesBuildPhase"
                let phase = phases.first { $0.isa == isa }?.id ?? addBuildPhase(isa, to: target)
                addBuildFile(fileReference: ref, to: phase)
            } else {
                var changed = false
                for phase in phases {
                    for bf in phase.references("files") where fileReference(ofBuildFile: bf)?.id == ref { removeBuildFile(bf); changed = true }
                }
                return changed
            }
        case .synchronized(let group, let rel):
            let key = SynchronizedFolder.membershipKey(forRelativePath: rel)
            guard isSynchronizedMember(key: key, folder: group, target: target) != member else { return false }
            let owns = self[target]?.references("fileSystemSynchronizedGroups").contains(group) == true
            let listed = owns != member
            if var set = exceptionSet(group: group, target: target) {
                var list = set.references("membershipExceptions")
                if listed { list.append(key); list.sort() } else { list.removeAll { $0 == key } }
                if list.isEmpty && set.attributes.keys.allSatisfy({ ["isa", "membershipExceptions", "target"].contains($0) }) {
                    if var g = self[group] {
                        let rest = g.references("exceptions").filter { $0 != set.id }
                        g["exceptions"] = rest.isEmpty ? nil : .array(rest.map(PlistValue.string))
                        self[group] = g
                    }
                    self[set.id] = nil
                } else {
                    set["membershipExceptions"] = list.isEmpty ? nil : .array(list.map(PlistValue.string))
                    self[set.id] = set
                }
            } else {
                guard listed else { return false }
                let id = makeObjectID()
                self[id] = PBXObject(id: id, attributes: PlistDictionary([
                    ("isa", .string("PBXFileSystemSynchronizedBuildFileExceptionSet")),
                    ("membershipExceptions", .array([.string(key)])),
                    ("target", .string(target)),
                ]))
                if var g = self[group] {
                    g["exceptions"] = .array((g.references("exceptions") + [id]).map(PlistValue.string))
                    self[group] = g
                }
            }
        }
        return true
    }

    mutating func addBuildPhase(_ isa: String, to target: String) -> String {
        let id = makeObjectID()
        self[id] = PBXObject(id: id, attributes: PlistDictionary([
            ("isa", .string(isa)), ("buildActionMask", .string("2147483647")), ("files", .array([])),
            ("runOnlyForDeploymentPostprocessing", .string("0")),
        ]))
        if var t = self[target] {
            t["buildPhases"] = .array((t.references("buildPhases") + [id]).map(PlistValue.string))
            self[target] = t
        }
        return id
    }

    static func isSource(_ path: String) -> Bool {
        ["swift", "m", "mm", "c", "cc", "cpp", "cxx", "metal", "s", "intentdefinition"].contains((path as NSString).pathExtension.lowercased())
    }
}
