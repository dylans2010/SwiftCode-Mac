import Foundation
import SwiftCodeBuild
import SwiftCodeProject

public struct DiscoveredTest: Equatable, Sendable, Hashable {
    public enum Kind: String, Sendable { case xctest, swiftTesting }
    public var file: String
    public var suite: String?
    public var name: String
    public var line: Int
    public var kind: Kind
    public var suiteLine: Int?

    public var identifier: String { suite.map { "\($0)/\(name)" } ?? name }

    public func matches(_ o: TestOutcome) -> Bool {
        o.name == name && (o.suite == nil || o.suite == suite)
    }
}

public enum TestDiscovery {
    public static func tests(in text: String, file: String) -> [DiscoveredTest] {
        let language = SourceTokenizer.Language(fileName: file)
        if language == .objc { return objcTests(in: text, file: file) }
        guard language == .swift else { return [] }
        var units = Array(text.utf16)
        for t in SourceTokenizer(language: .swift).tokens(in: text) where [.comment, .docComment, .string].contains(t.kind) {
            for i in t.range.location..<min(NSMaxRange(t.range), units.count) where units[i] != 10 { units[i] = 32 }
        }
        let clean = String(decoding: units, as: UTF16.self)
        let index = LineIndex(clean)
        let words = SymbolScanner.scanWords(clean)

        struct OpenType { var name: String; var memberDepth: Int; var isXCTest: Bool; var line: Int }
        var stack: [OpenType] = []
        var pendingType: (name: String, depth: Int, isXCTest: Bool, line: Int)?
        var testAttribute = false
        var out: [DiscoveredTest] = []
        let typeKeywords: Set<String> = ["class", "struct", "enum", "actor", "extension"]

        for (i, w) in words.enumerated() {
            switch w.text {
            case "{":
                if let p = pendingType, w.depth == p.depth {
                    stack.append(OpenType(name: p.name, memberDepth: p.depth + 1, isXCTest: p.isXCTest, line: p.line))
                    pendingType = nil
                }
                testAttribute = false
                continue
            case "}":
                while let last = stack.last, w.depth < last.memberDepth { stack.removeLast() }
                testAttribute = false
                continue
            case "@Test":
                testAttribute = true
                continue
            default:
                break
            }
            if pendingType != nil {
                if w.text == "XCTestCase" { pendingType!.isXCTest = true }
                continue
            }
            let next = i + 1 < words.count ? words[i + 1] : nil
            if typeKeywords.contains(w.text), let n = next, n.isIdentifier, n.text != "func", n.text != "var" {
                pendingType = (n.text, w.depth, false, index.line(at: w.offset))
                testAttribute = false
            } else if w.text == "func", let n = next, n.isIdentifier {
                let enclosing = stack.last.flatMap { $0.memberDepth == w.depth ? $0 : nil }
                let line = index.line(at: w.offset)
                if testAttribute {
                    out.append(DiscoveredTest(file: file, suite: enclosing?.name, name: n.text, line: line, kind: .swiftTesting, suiteLine: enclosing?.line))
                } else if let e = enclosing, e.isXCTest, n.text.hasPrefix("test") {
                    out.append(DiscoveredTest(file: file, suite: e.name, name: n.text, line: line, kind: .xctest, suiteLine: e.line))
                }
                testAttribute = false
            }
        }
        return out
    }

    public static func objcTests(in text: String, file: String) -> [DiscoveredTest] {
        var units = Array(text.utf16)
        for t in SourceTokenizer(language: .objc).tokens(in: text) where [.comment, .docComment, .string].contains(t.kind) {
            for i in t.range.location..<min(NSMaxRange(t.range), units.count) where units[i] != 10 { units[i] = 32 }
        }
        let lines = String(decoding: units, as: UTF16.self).components(separatedBy: "\n")
        var testClasses = Set<String>()
        for l in lines {
            let t = l.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("@interface ") else { continue }
            let parts = t.dropFirst(11).split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces).hasPrefix("XCTestCase") {
                testClasses.insert(parts[0].trimmingCharacters(in: .whitespaces))
            }
        }
        var out: [DiscoveredTest] = []
        var current: (name: String, line: Int)?
        for (i, l) in lines.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("@implementation ") {
                let name = t.dropFirst(16).split(whereSeparator: { $0 == " " || $0 == "{" }).first.map(String.init) ?? ""
                current = testClasses.contains(name) ? (name, i + 1) : nil
            } else if t.hasPrefix("@end") {
                current = nil
            } else if let c = current, t.hasPrefix("-") {
                let sig = t.dropFirst().trimmingCharacters(in: .whitespaces)
                guard sig.hasPrefix("(void)") else { continue }
                let rest = sig.dropFirst(6).trimmingCharacters(in: .whitespaces)
                let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                if name.hasPrefix("test"), !rest.dropFirst(name.count).trimmingCharacters(in: .whitespaces).hasPrefix(":") {
                    out.append(DiscoveredTest(file: file, suite: c.name, name: name, line: i + 1, kind: .xctest, suiteLine: c.line))
                }
            }
        }
        return out
    }

    public static func tests(in root: NavigatorNode) -> [DiscoveredTest] {
        root.allFiles.flatMap { node -> [DiscoveredTest] in
            guard let path = node.path, node.name.hasSuffix(".swift") || node.name.hasSuffix(".m") || node.name.hasSuffix(".mm"),
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
            return tests(in: text, file: path)
        }
    }
}

extension WorkspaceModel {
    public func targetName(compiling file: String) -> String? {
        let path = URL(fileURLWithPath: file).standardizedFileURL.path
        for (projPath, project) in projects.sorted(by: { $0.key < $1.key }) {
            let dir = project.projectDirectory(xcodeprojURL: URL(fileURLWithPath: projPath))
            let parents = project.parentMap()
            for t in project.targets {
                for phase in project.buildPhases(ofTarget: t.id) where phase.isa == "PBXSourcesBuildPhase" {
                    for bf in phase.references("files") {
                        if let ref = project.fileReference(ofBuildFile: bf),
                           let p = project.resolvedPath(of: ref.id, projectDirectory: dir, parents: parents),
                           URL(fileURLWithPath: p).standardizedFileURL.path == path { return t.string("name") }
                    }
                }
                for g in t.references("fileSystemSynchronizedGroups") {
                    if let p = project.resolvedPath(of: g, projectDirectory: dir, parents: parents),
                       path.hasPrefix(URL(fileURLWithPath: p).standardizedFileURL.path + "/") { return t.string("name") }
                }
            }
        }
        return nil
    }
}
